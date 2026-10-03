package server

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/minio/minio-go/v7"

	"anban/backend/internal/config"
	"anban/backend/internal/storage"
)

// Server routes authenticated requests to the feature handlers.
type Server struct {
	db        *sql.DB
	objects   *minio.Client
	bucket    string
	origins   map[string]bool
	mu        sync.Mutex
	attempts  map[string][]time.Time
	admins    map[string]bool
	publicURL string
}

// New connects the configured services before accepting requests.
func New(cfg config.Config) (*Server, error) {
	if err := cfg.Validate(); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	db, objects, err := storage.Open(ctx, cfg)
	if err != nil {
		return nil, err
	}
	s := &Server{db: db, objects: objects, bucket: cfg.MinIOBucket, origins: map[string]bool{}, attempts: map[string][]time.Time{}, admins: map[string]bool{}}
	s.publicURL = cfg.PublicURL
	for _, username := range cfg.AdminUsers {
		name := strings.ToLower(strings.TrimSpace(username))
		if name == "" {
			continue
		}
		var exists bool
		if err := db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM anban_users WHERE username=$1)`, name).Scan(&exists); err != nil || !exists {
			db.Close()
			return nil, fmt.Errorf("管理员账号 %q 不存在或读取失败，请先注册该账号再配置 ANBAN_ADMIN_USERS", name)
		}
		s.admins[name] = true
	}
	for _, origin := range cfg.Origins {
		s.origins[strings.TrimSpace(origin)] = true
	}
	return s, nil
}

func (c *Server) Close() error { return c.db.Close() }

func (c *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	if o := r.Header.Get("Origin"); o != "" {
		if !c.origins[o] {
			fail(w, 403, "origin is not allowed")
			return
		}
		w.Header().Set("Access-Control-Allow-Origin", o)
		w.Header().Set("Vary", "Origin")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, If-Match")
		w.Header().Set("Access-Control-Expose-Headers", "ETag")
	}
	if r.Method == "OPTIONS" {
		w.WriteHeader(204)
		return
	}
	if r.URL.Path == "/healthz" {
		writeJSON(w, 200, map[string]string{"status": "ok"})
		return
	}
	if r.URL.Path == "/api/v1/app/android-update" {
		c.publicAndroidUpdate(w, r)
		return
	}
	if strings.HasPrefix(r.URL.Path, "/api/v1/app/android-apk/") {
		c.downloadAPK(w, r)
		return
	}
	if r.URL.Path == "/api/v1/auth/register" || r.URL.Path == "/api/v1/auth/login" || r.URL.Path == "/api/v1/admin/login" {
		c.auth(w, r)
		return
	}
	token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	var user, username string
	if token == r.Header.Get("Authorization") || !filePattern.MatchString(token) {
		fail(w, 401, "请先登录")
		return
	}
	err := c.db.QueryRowContext(r.Context(), `SELECT u.id,u.username FROM anban_sessions s JOIN anban_users u ON u.id=s.user_id WHERE s.token_hash=$1 AND s.expires_at>now()`, tokenHash(token)).Scan(&user, &username)
	if err != nil {
		if err == sql.ErrNoRows {
			fail(w, 401, "登录已过期，请重新登录")
		} else {
			fail(w, 503, "账号服务暂不可用")
		}
		return
	}
	switch {
	case strings.HasPrefix(r.URL.Path, "/api/v1/admin/"):
		if !c.admins[username] {
			fail(w, 403, "此账号没有管理权限")
			return
		}
		c.admin(w, r, username)
	case r.URL.Path == "/api/v1/config/health-options":
		c.healthOptions(w, r)
	case r.URL.Path == "/api/v1/auth/me" && r.Method == "GET":
		writeJSON(w, 200, map[string]string{"userId": user, "username": username})
	case r.URL.Path == "/api/v1/auth/logout" && r.Method == "POST":
		if _, err := c.db.ExecContext(r.Context(), `DELETE FROM anban_sessions WHERE token_hash=$1`, tokenHash(token)); err != nil {
			fail(w, 500, "退出失败")
			return
		}
		writeJSON(w, 200, map[string]bool{"ok": true})
	case r.URL.Path == "/api/v1/vault":
		c.vault(w, r, user)
	case r.URL.Path == "/api/v1/files" || strings.HasPrefix(r.URL.Path, "/api/v1/files/"):
		c.file(w, r, user)
	default:
		fail(w, 404, "not found")
	}
}
