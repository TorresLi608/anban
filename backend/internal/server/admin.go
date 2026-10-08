package server

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"anban/backend/internal/config"
)

type releaseState struct {
	Revision  int64                  `json:"revision"`
	Enabled   bool                   `json:"enabled"`
	Release   *config.AndroidRelease `json:"release"`
	UpdatedAt time.Time              `json:"updatedAt"`
}

func readRelease(ctx context.Context, q interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}, lock bool) (releaseState, error) {
	query := `SELECT revision,enabled,release,updated_at FROM anban_android_release WHERE id=true`
	if lock {
		query += ` FOR UPDATE`
	}
	var state releaseState
	var raw []byte
	err := q.QueryRowContext(ctx, query).Scan(&state.Revision, &state.Enabled, &raw, &state.UpdatedAt)
	if err == nil && len(raw) > 0 {
		err = json.Unmarshal(raw, &state.Release)
	}
	return state, err
}

func (c *Server) publicAndroidUpdate(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		w.Header().Set("Allow", "GET")
		fail(w, 405, "method not allowed")
		return
	}
	state, err := readRelease(r.Context(), c.db, false)
	if err != nil {
		fail(w, 503, "更新服务暂不可用")
		return
	}
	if !state.Enabled || state.Release == nil {
		w.WriteHeader(204)
		return
	}
	writeJSON(w, 200, state.Release)
}

func (c *Server) admin(w http.ResponseWriter, r *http.Request, username string) {
	switch r.URL.Path {
	case "/api/v1/admin/me":
		if r.Method != "GET" {
			fail(w, 405, "method not allowed")
			return
		}
		writeJSON(w, 200, map[string]string{"username": username})
	case "/api/v1/admin/android-release":
		c.adminRelease(w, r)
	case "/api/v1/admin/health-options":
		c.adminHealthOptions(w, r)
	case "/api/v1/admin/apks":
		c.uploadAPK(w, r)
	case "/api/v1/admin/logout":
		if r.Method != "POST" {
			fail(w, 405, "method not allowed")
			return
		}
		c.mu.Lock()
		delete(c.adminSessions, tokenHash(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")))
		c.mu.Unlock()
		writeJSON(w, 200, map[string]bool{"ok": true})
	default:
		fail(w, 404, "not found")
	}
}

func (c *Server) adminRelease(w http.ResponseWriter, r *http.Request) {
	if r.Method == "GET" {
		state, err := readRelease(r.Context(), c.db, false)
		if err != nil {
			fail(w, 503, "版本信息读取失败")
			return
		}
		writeJSON(w, 200, state)
		return
	}
	if r.Method != "PUT" {
		fail(w, 405, "method not allowed")
		return
	}
	var in struct {
		Revision *int64                 `json:"revision"`
		Enabled  bool                   `json:"enabled"`
		Release  *config.AndroidRelease `json:"release"`
	}
	if !decode(w, r, &in, 16384) {
		return
	}
	if in.Revision == nil || *in.Revision < 0 {
		fail(w, 400, "缺少有效的编辑版本，请刷新页面")
		return
	}
	if in.Enabled && in.Release == nil {
		fail(w, 400, "请先填写版本信息")
		return
	}
	if in.Release != nil {
		if err := in.Release.Validate(); err != nil {
			fail(w, 400, err.Error())
			return
		}
	}
	tx, err := c.db.BeginTx(r.Context(), nil)
	if err != nil {
		fail(w, 503, "保存失败")
		return
	}
	defer tx.Rollback()
	current, err := readRelease(r.Context(), tx, true)
	if err != nil {
		fail(w, 503, "版本信息读取失败")
		return
	}
	if current.Revision != *in.Revision {
		fail(w, 409, "版本信息已被修改，请刷新页面后重新编辑")
		return
	}
	if current.Release != nil && (in.Release == nil || in.Release.VersionCode < current.Release.VersionCode) {
		fail(w, 400, "请保留已发布的版本信息，版本编号不能降低；暂停提示请关闭发布开关")
		return
	}
	raw, _ := json.Marshal(in.Release)
	var updated time.Time
	err = tx.QueryRowContext(r.Context(), `UPDATE anban_android_release SET revision=revision+1,enabled=$1,release=$2,updated_at=now() WHERE id=true RETURNING updated_at`, in.Enabled, string(raw)).Scan(&updated)
	if err != nil {
		fail(w, 500, "保存版本失败")
		return
	}
	if err = tx.Commit(); err != nil {
		fail(w, 500, "保存版本失败")
		return
	}
	writeJSON(w, 200, releaseState{current.Revision + 1, in.Enabled, in.Release, updated})
}

type healthState struct {
	Revision string              `json:"revision"`
	Options  map[string][]string `json:"options"`
}

func readHealthOptions(rows *sql.Rows) (healthState, error) {
	defer rows.Close()
	options := map[string][]string{}
	for rows.Next() {
		var key string
		var raw []byte
		var values []string
		if err := rows.Scan(&key, &raw); err != nil {
			return healthState{}, err
		}
		if err := json.Unmarshal(raw, &values); err != nil {
			return healthState{}, err
		}
		options[key] = values
	}
	if err := rows.Err(); err != nil {
		return healthState{}, err
	}
	raw, _ := json.Marshal(options)
	hash := sha256.Sum256(raw)
	return healthState{hex.EncodeToString(hash[:]), options}, nil
}

func validHealthOptions(options map[string][]string) bool {
	keys := []string{"stoolStatus", "urineStatus", "urineColor", "urineAppearance"}
	if len(options) != len(keys) {
		return false
	}
	for _, key := range keys {
		values := options[key]
		if len(values) == 0 || len(values) > 50 {
			return false
		}
		seen := map[string]bool{}
		for _, value := range values {
			if strings.TrimSpace(value) != value || value == "" || utf8.RuneCountInString(value) > 100 || strings.ContainsAny(value, "\r\n") || seen[value] {
				return false
			}
			seen[value] = true
		}
	}
	return true
}

func (c *Server) adminHealthOptions(w http.ResponseWriter, r *http.Request) {
	if r.Method == "GET" {
		rows, err := c.db.QueryContext(r.Context(), `SELECT key,options FROM anban_health_options ORDER BY key`)
		if err != nil {
			fail(w, 503, "健康选项读取失败")
			return
		}
		state, err := readHealthOptions(rows)
		if err != nil {
			fail(w, 503, "健康选项读取失败")
			return
		}
		writeJSON(w, 200, state)
		return
	}
	if r.Method != "PUT" {
		fail(w, 405, "method not allowed")
		return
	}
	var in healthState
	if !decode(w, r, &in, 131072) {
		return
	}
	if !filePattern.MatchString(in.Revision) || !validHealthOptions(in.Options) {
		fail(w, 400, "每组需 1–50 个不重复选项，每项最多 100 字，不可留空；请保留全部四组")
		return
	}
	tx, err := c.db.BeginTx(r.Context(), nil)
	if err != nil {
		fail(w, 503, "保存失败")
		return
	}
	defer tx.Rollback()
	rows, err := tx.QueryContext(r.Context(), `SELECT key,options FROM anban_health_options ORDER BY key FOR UPDATE`)
	if err != nil {
		fail(w, 503, "健康选项读取失败")
		return
	}
	current, err := readHealthOptions(rows)
	if err != nil {
		fail(w, 503, "健康选项读取失败")
		return
	}
	if current.Revision != in.Revision {
		fail(w, 409, "健康选项已被修改，请刷新页面后重新编辑")
		return
	}
	for key, values := range in.Options {
		raw, _ := json.Marshal(values)
		if _, err = tx.ExecContext(r.Context(), `UPDATE anban_health_options SET options=$2 WHERE key=$1`, key, string(raw)); err != nil {
			fail(w, 500, "保存健康选项失败")
			return
		}
	}
	if err = tx.Commit(); err != nil {
		fail(w, 500, "保存健康选项失败")
		return
	}
	raw, _ := json.Marshal(in.Options)
	hash := sha256.Sum256(raw)
	writeJSON(w, 200, healthState{hex.EncodeToString(hash[:]), in.Options})
}
