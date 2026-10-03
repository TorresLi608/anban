package server

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"net"
	"net/http"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"golang.org/x/crypto/bcrypt"
)

func randomID() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}
func tokenHash(token string) string {
	h := sha256.Sum256([]byte(token))
	return hex.EncodeToString(h[:])
}

// ponytail: per-process IP throttling; use a shared gateway limit before running multiple replicas.
func (c *Server) allow(r *http.Request) bool {
	ip, _, _ := net.SplitHostPort(r.RemoteAddr)
	c.mu.Lock()
	defer c.mu.Unlock()
	now := time.Now()
	for key, ts := range c.attempts {
		if len(ts) == 0 || now.Sub(ts[len(ts)-1]) > time.Minute {
			delete(c.attempts, key)
		}
	}
	ts := c.attempts[ip]
	fresh := ts[:0]
	for _, t := range ts {
		if now.Sub(t) < time.Minute {
			fresh = append(fresh, t)
		}
	}
	if len(fresh) >= 10 || len(c.attempts) >= 10000 {
		return false
	}
	c.attempts[ip] = append(fresh, now)
	return true
}

func validPassword(password string) bool {
	return utf8.RuneCountInString(password) >= 6 && len(password) <= 72
}

var usernamePattern = regexp.MustCompile(`^[a-z0-9_]{3,32}$`)
var filePattern = regexp.MustCompile(`^[a-f0-9]{64}$`)
var dummyHash, _ = bcrypt.GenerateFromPassword([]byte("unused-comparison-password"), bcrypt.DefaultCost)

func (c *Server) auth(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		fail(w, 405, "method not allowed")
		return
	}
	if !c.allow(r) {
		w.Header().Set("Retry-After", "60")
		fail(w, 429, "尝试过于频繁，请一分钟后重试")
		return
	}
	var in struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if !decode(w, r, &in, 4096) {
		return
	}
	in.Username = strings.ToLower(strings.TrimSpace(in.Username))
	if !usernamePattern.MatchString(in.Username) || !validPassword(in.Password) {
		fail(w, 400, "账号需 3–32 位字母、数字或下划线；密码至少 6 个字符，最多 72 字节")
		return
	}
	var id, hash string
	if r.URL.Path == "/api/v1/auth/register" {
		h, err := bcrypt.GenerateFromPassword([]byte(in.Password), bcrypt.DefaultCost)
		if err != nil {
			fail(w, 500, "注册失败")
			return
		}
		id = randomID()
		result, err := c.db.ExecContext(r.Context(), `INSERT INTO anban_users(id,username,password_hash) VALUES($1,$2,$3) ON CONFLICT(username) DO NOTHING`, id, in.Username, string(h))
		if err != nil {
			fail(w, 500, "注册失败")
			return
		}
		n, _ := result.RowsAffected()
		if n == 0 {
			fail(w, 409, "账号已存在")
			return
		}
	} else {
		err := c.db.QueryRowContext(r.Context(), `SELECT id,password_hash FROM anban_users WHERE username=$1`, in.Username).Scan(&id, &hash)
		if err != nil && err != sql.ErrNoRows {
			fail(w, 503, "登录服务暂不可用")
			return
		}
		if err == sql.ErrNoRows {
			hash = string(dummyHash)
		}
		if bcrypt.CompareHashAndPassword([]byte(hash), []byte(in.Password)) != nil || id == "" {
			fail(w, 401, "账号或密码错误")
			return
		}
	}
	token := randomID()
	expires := time.Now().Add(30 * 24 * time.Hour)
	_, err := c.db.ExecContext(r.Context(), `INSERT INTO anban_sessions(token_hash,user_id,expires_at) VALUES($1,$2,$3)`, tokenHash(token), id, expires)
	if err != nil {
		fail(w, 500, "无法建立会话，请重新登录")
		return
	}
	_, _ = c.db.ExecContext(r.Context(), `DELETE FROM anban_sessions WHERE expires_at < now()`)
	writeJSON(w, 200, map[string]any{"token": token, "userId": id, "username": in.Username, "expiresAt": expires})
}
