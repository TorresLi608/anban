package server

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"
	_ "time/tzdata"
)

type pushJob struct {
	Key   string    `json:"key"`
	At    time.Time `json:"at"`
	Daily string    `json:"daily"`
}

type pushPlan struct {
	Enabled  bool      `json:"enabled"`
	TimeZone string    `json:"timeZone"`
	Revision uint64    `json:"revision"`
	Jobs     []pushJob `json:"jobs"`
}

var pushKey = regexp.MustCompile(`^[a-zA-Z0-9:_-]{1,100}$`)
var dailyTime = regexp.MustCompile(`^([01][0-9]|2[0-3]):[0-5][0-9]$`)

// ntfy topic names are limited in length. The first 40 hex characters still
// provide 160 bits of per-account namespace while keeping the public topic
// below that limit.
func pushTopic(user string) string {
	if len(user) > 40 {
		user = user[:40]
	}
	return "anban-" + user
}

func validatePushPlan(p pushPlan, now time.Time) error {
	zone, err := time.LoadLocation(p.TimeZone)
	if err != nil || len(p.Jobs) > 450 || (!p.Enabled && len(p.Jobs) != 0) {
		return errors.New("提醒时区或排程无效，最多450项")
	}
	seen := map[string]bool{}
	for _, j := range p.Jobs {
		if !pushKey.MatchString(j.Key) || j.Key == "test" || seen[j.Key] || j.At.Before(now.Add(-time.Minute)) || j.At.After(now.Add(15*24*time.Hour)) || (j.Daily != "" && (!dailyTime.MatchString(j.Daily) || j.At.In(zone).Format("15:04") != j.Daily)) {
			return errors.New("提醒标识、时间或循环时间无效")
		}
		seen[j.Key] = true
	}
	return nil
}

func (c *Server) remoteReminders(w http.ResponseWriter, r *http.Request, user string) {
	configured := c.ntfyPublicURL != "" && c.ntfyToken != ""
	if !configured && r.Method != "PUT" {
		fail(w, 503, "后端尚未配置 ntfy 地址和发布凭据")
		return
	}
	if r.URL.Path == "/api/v1/reminders/test" {
		if r.Method != "POST" {
			fail(w, 405, "method not allowed")
			return
		}
		if !c.allow(r) {
			fail(w, 429, "测试过于频繁，请稍后重试")
			return
		}
		at := time.Now().UTC().Add(time.Minute)
		tx, err := c.db.BeginTx(r.Context(), nil)
		if err != nil {
			fail(w, 503, "提醒数据库不可用")
			return
		}
		defer tx.Rollback()
		_, err = tx.ExecContext(r.Context(), `INSERT INTO anban_push_settings(user_id) VALUES($1) ON CONFLICT DO NOTHING`, user)
		if err == nil {
			_, err = tx.ExecContext(r.Context(), `SELECT user_id FROM anban_push_settings WHERE user_id=$1 FOR UPDATE`, user)
		}
		if err == nil {
			_, err = tx.ExecContext(r.Context(), `INSERT INTO anban_push_jobs(user_id,key,due_at) VALUES($1,'test',$2) ON CONFLICT(user_id,key) DO UPDATE SET due_at=excluded.due_at,retry_at=now()`, user, at)
		}
		if err != nil || tx.Commit() != nil {
			fail(w, 503, "无法安排后端测试")
			return
		}
		writeJSON(w, 200, map[string]any{"at": at, "topic": pushTopic(user), "server": c.ntfyPublicURL})
		return
	}
	if r.Method == "GET" {
		var enabled bool
		var success sql.NullTime
		var lastError string
		err := c.db.QueryRowContext(r.Context(), `SELECT enabled,last_success,last_error FROM anban_push_settings WHERE user_id=$1`, user).Scan(&enabled, &success, &lastError)
		if err != nil && err != sql.ErrNoRows {
			fail(w, 503, "无法读取推送状态")
			return
		}
		var count int
		if c.db.QueryRowContext(r.Context(), `SELECT count(*) FROM anban_push_jobs WHERE user_id=$1`, user).Scan(&count) != nil {
			fail(w, 503, "无法读取推送队列")
			return
		}
		var sent any
		if success.Valid {
			sent = success.Time
		}
		writeJSON(w, 200, map[string]any{"enabled": enabled, "topic": pushTopic(user), "server": c.ntfyPublicURL, "pending": count, "lastSuccess": sent, "lastError": lastError})
		return
	}
	if r.Method != "PUT" {
		fail(w, 405, "method not allowed")
		return
	}
	var plan pushPlan
	if !decode(w, r, &plan, 128<<10) {
		return
	}
	if err := validatePushPlan(plan, time.Now()); err != nil {
		fail(w, 400, err.Error())
		return
	}
	if plan.Enabled && !configured {
		fail(w, 503, "后端尚未配置 ntfy 发布凭据")
		return
	}
	tx, err := c.db.BeginTx(r.Context(), nil)
	if err != nil {
		fail(w, 503, "提醒数据库不可用")
		return
	}
	defer tx.Rollback()
	var revision uint64
	if tx.QueryRowContext(r.Context(), `SELECT revision FROM anban_vaults WHERE user_id=$1 FOR SHARE`, user).Scan(&revision) != nil || revision != plan.Revision {
		fail(w, 409, "资料已更新，请重新同步提醒")
		return
	}
	_, err = tx.ExecContext(r.Context(), `INSERT INTO anban_push_settings(user_id,enabled,time_zone) VALUES($1,$2,$3) ON CONFLICT(user_id) DO UPDATE SET enabled=excluded.enabled,time_zone=excluded.time_zone,last_error=''`, user, plan.Enabled, plan.TimeZone)
	if err == nil {
		_, err = tx.ExecContext(r.Context(), `DELETE FROM anban_push_jobs WHERE user_id=$1 AND key<>'test'`, user)
	}
	for _, j := range plan.Jobs {
		if err != nil {
			break
		}
		_, err = tx.ExecContext(r.Context(), `INSERT INTO anban_push_jobs(user_id,key,due_at,daily_time) VALUES($1,$2,$3,$4)`, user, j.Key, j.At, j.Daily)
	}
	if err != nil || tx.Commit() != nil {
		fail(w, 503, "后端提醒保存失败")
		return
	}
	writeJSON(w, 200, map[string]any{"pending": len(plan.Jobs)})
}

func publishNtfy(ctx context.Context, base, token, topic string, test bool) error {
	body := "有一项提醒到时间了，请打开安伴核对。"
	if test {
		body = "这是一条后端定时测试通知，点击打开安伴。"
	}
	request, err := http.NewRequestWithContext(ctx, "POST", base+"/"+topic, strings.NewReader(body))
	if err != nil {
		return err
	}
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("Title", "Anban")
	request.Header.Set("Click", "anban://reminders")
	request.Header.Set("Priority", "4")
	client := &http.Client{Timeout: 10 * time.Second, CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}
	response, err := client.Do(request)
	if err != nil {
		return errors.New("ntfy 连接失败")
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("ntfy 返回 HTTP %d", response.StatusCode)
	}
	return nil
}

func nextDaily(at, now time.Time, clock, zone string) (time.Time, error) {
	loc, err := time.LoadLocation(zone)
	if err != nil {
		return time.Time{}, err
	}
	parsed, err := time.Parse("15:04", clock)
	if err != nil {
		return time.Time{}, err
	}
	day := at.In(loc)
	next := time.Date(day.Year(), day.Month(), day.Day()+1, parsed.Hour(), parsed.Minute(), 0, 0, loc)
	for !next.After(now) {
		next = next.AddDate(0, 0, 1)
	}
	return next, nil
}

func (c *Server) startPushWorker() {
	ctx, cancel := context.WithCancel(context.Background())
	c.pushCancel = cancel
	c.pushDone = make(chan struct{})
	go func() {
		defer close(c.pushDone)
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				for i := 0; i < 50; i++ {
					if !c.deliverPush(ctx) {
						break
					}
				}
			}
		}
	}()
}

// Row locks serialize sending with settings changes and allow multiple workers.
func (c *Server) deliverPush(ctx context.Context) bool {
	tx, err := c.db.BeginTx(ctx, nil)
	if err != nil {
		return false
	}
	defer tx.Rollback()
	var user, zone string
	err = tx.QueryRowContext(ctx, `SELECT s.user_id,s.time_zone FROM anban_push_settings s WHERE EXISTS(SELECT 1 FROM anban_push_jobs j WHERE j.user_id=s.user_id AND (s.enabled OR j.key='test') AND j.due_at<=now() AND j.retry_at<=now()) ORDER BY s.user_id LIMIT 1 FOR UPDATE OF s SKIP LOCKED`).Scan(&user, &zone)
	if err != nil {
		return false
	}
	rows, err := tx.QueryContext(ctx, `SELECT key,due_at,daily_time FROM anban_push_jobs WHERE user_id=$1 AND due_at<=now() AND retry_at<=now() ORDER BY due_at`, user)
	if err != nil {
		return false
	}
	var jobs []pushJob
	for rows.Next() {
		var j pushJob
		if rows.Scan(&j.Key, &j.At, &j.Daily) != nil {
			rows.Close()
			return false
		}
		jobs = append(jobs, j)
	}
	err = rows.Err()
	rows.Close()
	if err != nil || len(jobs) == 0 {
		return false
	}
	now := time.Now()
	test, fresh := false, false
	for _, j := range jobs {
		test = test || j.Key == "test"
		fresh = fresh || now.Sub(j.At) < 15*time.Minute
	}
	if fresh {
		err = publishNtfy(ctx, c.ntfyURL, c.ntfyToken, pushTopic(user), test)
	}
	if err != nil {
		_, err = tx.ExecContext(ctx, `UPDATE anban_push_settings SET last_error=$2 WHERE user_id=$1`, user, err.Error())
		if err == nil {
			_, err = tx.ExecContext(ctx, `UPDATE anban_push_jobs SET retry_at=now()+interval '1 minute' WHERE user_id=$1 AND due_at<=now()`, user)
		}
	} else {
		for _, j := range jobs {
			if j.Daily == "" {
				_, err = tx.ExecContext(ctx, `DELETE FROM anban_push_jobs WHERE user_id=$1 AND key=$2`, user, j.Key)
			} else {
				var next time.Time
				next, err = nextDaily(j.At, now, j.Daily, zone)
				if err == nil {
					_, err = tx.ExecContext(ctx, `UPDATE anban_push_jobs SET due_at=$3,retry_at=now() WHERE user_id=$1 AND key=$2`, user, j.Key, next)
				}
			}
			if err != nil {
				break
			}
		}
		if err == nil && fresh {
			_, err = tx.ExecContext(ctx, `UPDATE anban_push_settings SET last_success=now(),last_error='' WHERE user_id=$1`, user)
		}
	}
	return err == nil && tx.Commit() == nil
}
