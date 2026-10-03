package server

import (
	"encoding/json"
	"net/http"
	"time"
)

func (c *Server) vault(w http.ResponseWriter, r *http.Request, user string) {
	if r.Method != "GET" && r.Method != "PUT" && r.Method != "DELETE" {
		fail(w, 405, "method not allowed")
		return
	}
	var e *envelope
	if r.Method == "PUT" {
		e = &envelope{}
		if !decode(w, r, e, maxBody) {
			return
		}
		if !validEnvelope(e) {
			fail(w, 400, "invalid encryption envelope")
			return
		}
	}
	tx, err := c.db.BeginTx(r.Context(), nil)
	if err != nil {
		fail(w, 503, "数据库不可用")
		return
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(r.Context(), `INSERT INTO anban_vaults(user_id) VALUES($1) ON CONFLICT DO NOTHING`, user); err != nil {
		fail(w, 500, "读取失败")
		return
	}
	var rev uint64
	var updated time.Time
	var data []byte
	if err = tx.QueryRowContext(r.Context(), `SELECT revision,updated_at,data FROM anban_vaults WHERE user_id=$1 FOR UPDATE`, user).Scan(&rev, &updated, &data); err != nil {
		fail(w, 500, "读取失败")
		return
	}
	etag := func(n uint64) string { b, _ := json.Marshal(n); return `"` + string(b) + `"` }
	w.Header().Set("ETag", etag(rev))
	if r.Method == "GET" {
		var saved *envelope
		if len(data) > 0 {
			if json.Unmarshal(data, &saved) != nil {
				fail(w, 500, "快照损坏")
				return
			}
		}
		if tx.Commit() != nil {
			fail(w, 500, "读取失败")
			return
		}
		writeJSON(w, 200, snapshot{rev, updated.UTC().Format(time.RFC3339), saved})
		return
	}
	if r.Header.Get("If-Match") == "" {
		fail(w, 428, "If-Match revision is required")
		return
	}
	if r.Header.Get("If-Match") != etag(rev) {
		fail(w, 409, "远端已有新版本，请先拉取")
		return
	}
	var payload any
	if e != nil {
		b, _ := json.Marshal(e)
		payload = string(b)
	}
	updated = time.Now().UTC()
	if _, err = tx.ExecContext(r.Context(), `UPDATE anban_vaults SET revision=revision+1,updated_at=$2,data=$3 WHERE user_id=$1`, user, updated, payload); err != nil {
		fail(w, 500, "保存失败")
		return
	}
	if tx.Commit() != nil {
		fail(w, 500, "保存失败")
		return
	}
	w.Header().Set("ETag", etag(rev+1))
	writeJSON(w, 200, map[string]any{"revision": rev + 1, "updatedAt": updated})
}
