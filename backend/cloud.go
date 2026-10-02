package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"golang.org/x/crypto/bcrypt"
)

type cloud struct {
	db       *sql.DB
	objects  *minio.Client
	bucket   string
	origins  map[string]bool
	mu       sync.Mutex
	attempts map[string][]time.Time
}

func newCloud() (*cloud, error) {
	if os.Getenv("DATABASE_URL") == "" || os.Getenv("MINIO_ENDPOINT") == "" || os.Getenv("MINIO_ACCESS_KEY") == "" || os.Getenv("MINIO_SECRET_KEY") == "" {
		return nil, errors.New("DATABASE_URL and MINIO_ENDPOINT/ACCESS_KEY/SECRET_KEY are required")
	}
	db, err := sql.Open("pgx", os.Getenv("DATABASE_URL"))
	if err != nil {
		return nil, errors.New("invalid database configuration")
	}
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(30 * time.Minute)
	ok := false
	defer func() {
		if !ok {
			db.Close()
		}
	}()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err = db.PingContext(ctx); err != nil {
		return nil, errors.New("PostgreSQL connection failed; check DATABASE_URL")
	}
	_, err = db.ExecContext(ctx, `
 CREATE TABLE IF NOT EXISTS anban_health_options (key text PRIMARY KEY, options jsonb NOT NULL CHECK (jsonb_typeof(options) = 'array'));
 CREATE TABLE IF NOT EXISTS anban_users (id text PRIMARY KEY, username text NOT NULL UNIQUE, password_hash text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
 CREATE TABLE IF NOT EXISTS anban_sessions (token_hash text PRIMARY KEY, user_id text NOT NULL REFERENCES anban_users(id) ON DELETE CASCADE, expires_at timestamptz NOT NULL);
 CREATE INDEX IF NOT EXISTS anban_sessions_expiry ON anban_sessions(expires_at);
 CREATE TABLE IF NOT EXISTS anban_vaults (user_id text PRIMARY KEY REFERENCES anban_users(id) ON DELETE CASCADE, revision bigint NOT NULL DEFAULT 0, updated_at timestamptz NOT NULL DEFAULT now(), data jsonb);
 CREATE TABLE IF NOT EXISTS anban_files (id text PRIMARY KEY, user_id text NOT NULL REFERENCES anban_users(id) ON DELETE CASCADE, created_at timestamptz NOT NULL DEFAULT now());`)
	if err != nil {
		return nil, errors.New("database schema initialization failed")
	}
	for key, options := range healthDefaults {
		raw, _ := json.Marshal(options)
		if _, err = db.ExecContext(ctx, `INSERT INTO anban_health_options(key,options) VALUES($1,$2) ON CONFLICT(key) DO NOTHING`, key, string(raw)); err != nil {
			return nil, errors.New("health options initialization failed")
		}
	}
	objects, err := minio.New(os.Getenv("MINIO_ENDPOINT"), &minio.Options{Creds: credentials.NewStaticV4(os.Getenv("MINIO_ACCESS_KEY"), os.Getenv("MINIO_SECRET_KEY"), ""), Secure: env("MINIO_USE_SSL", "true") == "true"})
	if err != nil {
		return nil, err
	}
	c := &cloud{db: db, objects: objects, bucket: env("MINIO_BUCKET", "anban"), origins: map[string]bool{}, attempts: map[string][]time.Time{}}
	for _, origin := range strings.Split(os.Getenv("ANBAN_ORIGINS"), ",") {
		c.origins[strings.TrimSpace(origin)] = true
	}
	exists, err := objects.BucketExists(ctx, c.bucket)
	if err != nil || !exists {
		return nil, errors.New("MinIO bucket unavailable; check S3 API endpoint and create private bucket")
	}
	ok = true
	return c, nil
}
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
func decode(w http.ResponseWriter, r *http.Request, v any, limit int64) bool {
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	defer r.Body.Close()
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if d.Decode(v) != nil || d.Decode(&struct{}{}) != io.EOF {
		fail(w, 400, "请求格式错误或内容过大")
		return false
	}
	return true
}

// ponytail: per-process IP throttling; use a shared gateway limit before running multiple replicas.
func (c *cloud) allow(r *http.Request) bool {
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

func (c *cloud) auth(w http.ResponseWriter, r *http.Request) {
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
func (c *cloud) ServeHTTP(w http.ResponseWriter, r *http.Request) {
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
	if r.URL.Path == "/api/v1/auth/register" || r.URL.Path == "/api/v1/auth/login" {
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
func (c *cloud) vault(w http.ResponseWriter, r *http.Request, user string) {
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

const maxFile = 40 << 20 // 20 MB attachment plus base64 and encryption envelope.
func (c *cloud) file(w http.ResponseWriter, r *http.Request, user string) {
	if r.URL.Path == "/api/v1/files" && r.Method == "POST" {
		var e envelope
		if !decode(w, r, &e, maxFile) {
			return
		}
		// File envelopes use the same format with a larger ciphertext allowance.
		if !validFileEnvelope(&e) {
			fail(w, 400, "invalid encrypted file")
			return
		}
		b, _ := json.Marshal(e)
		id := randomID()
		key := user + "/" + id
		if _, err := c.objects.PutObject(r.Context(), c.bucket, key, bytes.NewReader(b), int64(len(b)), minio.PutObjectOptions{ContentType: "application/octet-stream"}); err != nil {
			fail(w, 502, "附件上传失败")
			return
		}
		if _, err := c.db.ExecContext(r.Context(), `INSERT INTO anban_files(id,user_id) VALUES($1,$2)`, id, user); err != nil {
			_ = c.objects.RemoveObject(r.Context(), c.bucket, key, minio.RemoveObjectOptions{})
			fail(w, 500, "附件索引保存失败")
			return
		}
		writeJSON(w, 200, map[string]string{"id": id})
		return
	}
	id := strings.TrimPrefix(r.URL.Path, "/api/v1/files/")
	if !filePattern.MatchString(id) {
		fail(w, 404, "附件不存在")
		return
	}
	if r.Method != "GET" {
		fail(w, 405, "method not allowed")
		return
	}
	var exists bool
	if err := c.db.QueryRowContext(r.Context(), `SELECT EXISTS(SELECT 1 FROM anban_files WHERE id=$1 AND user_id=$2)`, id, user).Scan(&exists); err != nil {
		fail(w, 503, "附件索引不可用")
		return
	}
	if !exists {
		fail(w, 404, "附件不存在")
		return
	}
	object, err := c.objects.GetObject(r.Context(), c.bucket, user+"/"+id, minio.GetObjectOptions{})
	if err != nil {
		fail(w, 502, "附件读取失败")
		return
	}
	defer object.Close()
	b, err := io.ReadAll(io.LimitReader(object, maxFile+1))
	if err != nil || len(b) > maxFile {
		fail(w, 502, "附件读取失败")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Write(b)
}
func validFileEnvelope(e *envelope) bool {
	clone := *e
	clone.Ciphertext = "AA=="
	if !validEnvelope(&clone) {
		return false
	}
	b, err := base64.StdEncoding.DecodeString(e.Ciphertext)
	return err == nil && len(b) > 0 && len(b) <= 28<<20
}
