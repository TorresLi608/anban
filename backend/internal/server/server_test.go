package server

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/minio/minio-go/v7"

	"anban/backend/internal/config"
)

func sampleEnvelope() envelope {
	b64 := func(n int) string { return base64.StdEncoding.EncodeToString(make([]byte, n)) }
	return envelope{1, "AES-256-GCM", 210000, b64(16), b64(12), b64(30), b64(16)}
}
func TestValidationAndThrottle(t *testing.T) {
	e := sampleEnvelope()
	if !validEnvelope(&e) || !validFileEnvelope(&e) {
		t.Fatal("valid envelope rejected")
	}
	e.Nonce = "bad"
	if validEnvelope(&e) || validFileEnvelope(&e) {
		t.Fatal("invalid nonce accepted")
	}
	c := &Server{attempts: map[string][]time.Time{}}
	r := httptest.NewRequest("POST", "/", nil)
	for i := 0; i < 10; i++ {
		if !c.allow(r) {
			t.Fatal("early rate limit")
		}
	}
	if c.allow(r) {
		t.Fatal("rate limit missing")
	}
	for _, name := range []string{"../user", "ab", "用户", "a b"} {
		if usernamePattern.MatchString(name) {
			t.Fatal("invalid username accepted")
		}
	}
	w := httptest.NewRecorder()
	r = httptest.NewRequest("POST", "/", strings.NewReader(`{"version":1} {}`))
	if decode(w, r, &e, 1024) {
		t.Fatal("trailing JSON accepted")
	}
}

// Run explicitly against configured services; creates and removes only randomized test users/files.
func TestCloudIntegration(t *testing.T) {
	if os.Getenv("ANBAN_INTEGRATION") != "1" {
		t.Skip("set ANBAN_INTEGRATION=1 with server environment")
	}
	c, err := New(config.Load())
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	var users []string
	var keys []string
	defer func() {
		for _, key := range keys {
			_ = c.objects.RemoveObject(context.Background(), c.bucket, key, minio.RemoveObjectOptions{})
		}
		for _, u := range users {
			_, _ = c.db.Exec(`DELETE FROM anban_users WHERE id=$1`, u)
		}
	}()
	request := func(method, path, token, match string, body any) *httptest.ResponseRecorder {
		b, _ := json.Marshal(body)
		r := httptest.NewRequest(method, path, bytes.NewReader(b))
		if token != "" {
			r.Header.Set("Authorization", "Bearer "+token)
		}
		r.Header.Set("If-Match", match)
		w := httptest.NewRecorder()
		c.ServeHTTP(w, r)
		return w
	}
	unpack := func(w *httptest.ResponseRecorder) map[string]any {
		t.Helper()
		if w.Code != 200 {
			t.Fatalf("status %d: %s", w.Code, w.Body)
		}
		var v map[string]any
		if json.Unmarshal(w.Body.Bytes(), &v) != nil {
			t.Fatal("invalid JSON")
		}
		return v
	}
	name := "test_" + randomID()[:16]
	creds := map[string]string{"username": name, "password": "abc123"}
	a := unpack(request("POST", "/api/v1/auth/register", "", "", creds))
	users = append(users, a["userId"].(string))
	token := a["token"].(string)
	options := unpack(request("GET", "/api/v1/config/health-options", token, "", nil))
	if len(options["stoolStatus"].([]any)) == 0 {
		t.Fatal("missing database options")
	}
	if request("GET", "/api/v1/config/health-options", "", "", nil).Code != 401 {
		t.Fatal("unauthorized config access")
	}

	if request("POST", "/api/v1/auth/register", "", "", creds).Code != 409 {
		t.Fatal("duplicate registration accepted")
	}
	creds["username"] = name + "b"
	b := unpack(request("POST", "/api/v1/auth/register", "", "", creds))
	users = append(users, b["userId"].(string))
	other := b["token"].(string)
	creds["username"] = name
	creds["password"] = "wrong-password-1234"
	if request("POST", "/api/v1/auth/login", "", "", creds).Code != 401 {
		t.Fatal("wrong password accepted")
	}
	creds["password"] = "abc123"
	unpack(request("POST", "/api/v1/auth/login", "", "", creds))
	if request("GET", "/api/v1/vault", "", "", nil).Code != 401 {
		t.Fatal("unauthenticated vault access")
	}
	if request("PUT", "/api/v1/vault", token, "", sampleEnvelope()).Code != 428 {
		t.Fatal("missing revision accepted")
	}
	unpack(request("PUT", "/api/v1/vault", token, `"0"`, sampleEnvelope()))
	if request("PUT", "/api/v1/vault", token, `"0"`, sampleEnvelope()).Code != 409 {
		t.Fatal("stale write accepted")
	}
	state := unpack(request("GET", "/api/v1/vault", other, "", nil))
	if state["data"] != nil {
		t.Fatal("cross-user vault leak")
	}
	file := unpack(request("POST", "/api/v1/files", token, "", sampleEnvelope()))
	id := file["id"].(string)
	keys = append(keys, users[0]+"/"+id)
	unpack(request("GET", "/api/v1/files/"+id, token, "", nil))
	if request("GET", "/api/v1/files/"+id, other, "", nil).Code != 404 {
		t.Fatal("cross-user file leak")
	}
	unpack(request("POST", "/api/v1/auth/logout", token, "", nil))
	if request("GET", "/api/v1/auth/me", token, "", nil).Code != 401 {
		t.Fatal("revoked session accepted")
	}
}

func TestPasswordLength(t *testing.T) {
	for _, p := range []string{"", "12345", "密码太短", strings.Repeat("a", 73)} {
		if validPassword(p) {
			t.Fatalf("accepted invalid password length: %d", len(p))
		}
	}
	for _, p := range []string{"abc123", "中文密码六个", strings.Repeat("a", 72)} {
		if !validPassword(p) {
			t.Fatal("rejected valid password")
		}
	}
}

func TestAdminRequiresAuthentication(t *testing.T) {
	s := &Server{}
	for _, path := range []string{"/api/v1/admin/me", "/api/v1/admin/android-release", "/api/v1/admin/health-options", "/api/v1/admin/logout"} {
		w := httptest.NewRecorder()
		s.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != 401 {
			t.Fatalf("unauthenticated admin route %s: %d", path, w.Code)
		}
	}
	w := httptest.NewRecorder()
	s.ServeHTTP(w, httptest.NewRequest("POST", "/api/v1/app/android-update", nil))
	if w.Code != 405 {
		t.Fatal("public update endpoint accepted a write")
	}
}

func TestHealthOptionsValidation(t *testing.T) {
	valid := map[string][]string{"stoolStatus": {"正常"}, "urineStatus": {"正常"}, "urineColor": {"浅黄"}, "urineAppearance": {"清澈"}}
	if !validHealthOptions(valid) {
		t.Fatal("valid health options rejected")
	}
	for _, values := range [][]string{nil, {}, {""}, {" 正常"}, {"正常", "正常"}, {strings.Repeat("字", 101)}, {"一\n二"}} {
		valid["stoolStatus"] = values
		if validHealthOptions(valid) {
			t.Fatal("invalid health options accepted")
		}
	}
}
