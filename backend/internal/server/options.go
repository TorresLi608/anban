package server

import (
	"encoding/json"
	"net/http"
)

func (c *Server) healthOptions(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		fail(w, 405, "method not allowed")
		return
	}
	rows, err := c.db.QueryContext(r.Context(), `SELECT key,options FROM anban_health_options ORDER BY key`)
	if err != nil {
		fail(w, 503, "配置读取失败")
		return
	}
	defer rows.Close()
	result := map[string][]string{}
	for rows.Next() {
		var key string
		var raw []byte
		var options []string
		if rows.Scan(&key, &raw) != nil || json.Unmarshal(raw, &options) != nil {
			fail(w, 500, "选项配置无效")
			return
		}
		result[key] = options
	}
	if rows.Err() != nil {
		fail(w, 503, "配置读取失败")
		return
	}
	writeJSON(w, 200, result)
}
