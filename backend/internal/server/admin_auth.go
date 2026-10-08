package server

import (
	"net/http"
	"time"

	"golang.org/x/crypto/bcrypt"
)

func (c *Server) loginAdmin(w http.ResponseWriter, r *http.Request, username, password string) {
	hash := c.adminPasswordHash
	if len(hash) == 0 {
		hash = dummyHash
	}
	if bcrypt.CompareHashAndPassword(hash, []byte(password)) != nil || len(c.adminPasswordHash) == 0 || username != c.adminUsername {
		fail(w, 401, "管理端账号或密码错误")
		return
	}

	now := time.Now()
	token := randomID()
	expires := now.Add(8 * time.Hour)
	c.mu.Lock()
	for hash, expiry := range c.adminSessions {
		if !expiry.After(now) {
			delete(c.adminSessions, hash)
		}
	}
	if len(c.adminSessions) >= 10000 {
		c.mu.Unlock()
		fail(w, 503, "管理端会话过多，请稍后重试")
		return
	}
	// ponytail: single-process admin sessions; use a shared session store before scaling replicas.
	// Restarting the backend revokes all admin sessions, including after credential changes.
	c.adminSessions[tokenHash(token)] = expires
	c.mu.Unlock()
	writeJSON(w, 200, map[string]any{"token": token, "username": c.adminUsername, "expiresAt": expires})
}

func (c *Server) validAdminSession(token string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	hash := tokenHash(token)
	if !c.adminSessions[hash].After(time.Now()) {
		delete(c.adminSessions, hash)
		return false
	}
	return len(c.adminPasswordHash) > 0
}
