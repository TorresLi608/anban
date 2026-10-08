package server

import (
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"
)

func TestIndependentAdminAuth(t *testing.T) {
	hash, err := bcrypt.GenerateFromPassword([]byte("admin-secret"), bcrypt.MinCost)
	if err != nil {
		t.Fatal(err)
	}
	newServer := func() *Server {
		return &Server{adminUsername: "operator", adminPasswordHash: hash, adminSessions: map[string]time.Time{}, attempts: map[string][]time.Time{}}
	}
	s := newServer() // No database: admin login must not depend on App registration.
	request := func(method, path, token, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, path, strings.NewReader(body))
		if token != "" {
			r.Header.Set("Authorization", "Bearer "+token)
		}
		w := httptest.NewRecorder()
		s.ServeHTTP(w, r)
		return w
	}
	login := func() string {
		t.Helper()
		w := request("POST", "/api/v1/admin/login", "", `{"username":" OPERATOR ","password":"admin-secret"}`)
		var session struct {
			Token     string    `json:"token"`
			ExpiresAt time.Time `json:"expiresAt"`
		}
		if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &session) != nil || !filePattern.MatchString(session.Token) {
			t.Fatalf("admin login failed: %d", w.Code)
		}
		if time.Until(session.ExpiresAt) > 8*time.Hour || time.Until(session.ExpiresAt) < 7*time.Hour {
			t.Fatal("unexpected session duration")
		}
		return session.Token
	}
	for _, body := range []string{
		`{"username":"operator","password":"wrong-password"}`,
		`{"username":"another_user","password":"admin-secret"}`,
	} {
		if request("POST", "/api/v1/admin/login", "", body).Code != 401 {
			t.Fatal("invalid credentials accepted")
		}
	}
	token := login()
	if _, exists := s.adminSessions[token]; exists {
		t.Fatal("raw session token stored")
	}
	if request("GET", "/api/v1/admin/me", token, "").Code != 200 || request("GET", "/api/v1/admin/me", randomID(), "").Code != 401 {
		t.Fatal("session validation failed")
	}
	// Reads and logout can run concurrently without racing on the session map.
	var requests sync.WaitGroup
	for i := 0; i < 20; i++ {
		requests.Add(1)
		go func() {
			defer requests.Done()
			request("GET", "/api/v1/admin/me", token, "")
		}()
	}
	if request("POST", "/api/v1/admin/logout", token, "").Code != 200 {
		t.Fatal("logout failed")
	}
	requests.Wait()
	if request("GET", "/api/v1/admin/me", token, "").Code != 401 {
		t.Fatal("logged-out token accepted")
	}
	token = login()
	s.adminSessions[tokenHash(token)] = time.Now().Add(-time.Second)
	if request("GET", "/api/v1/admin/me", token, "").Code != 401 {
		t.Fatal("expired session accepted")
	}
	token = login()
	s = newServer()
	if request("GET", "/api/v1/admin/me", token, "").Code != 401 {
		t.Fatal("restart retained an old session")
	}
	s.adminPasswordHash = nil
	if request("POST", "/api/v1/admin/login", "", `{"username":"operator","password":"unused-comparison-password"}`).Code != 401 {
		t.Fatal("unconfigured admin login enabled")
	}
	s = newServer()
	for i := 0; i < 11; i++ {
		code := request("POST", "/api/v1/admin/login", "", `{"username":"operator","password":"wrong-password"}`).Code
		if (i < 10 && code != 401) || (i == 10 && code != 429) {
			t.Fatal("admin login rate limit failed")
		}
	}
	s = newServer()
	for i := 0; i < 10000; i++ {
		s.adminSessions[fmt.Sprint(i)] = time.Now().Add(time.Hour)
	}
	if request("POST", "/api/v1/admin/login", "", `{"username":"operator","password":"admin-secret"}`).Code != 503 {
		t.Fatal("unbounded session growth")
	}
	for key := range s.adminSessions {
		s.adminSessions[key] = time.Now().Add(-time.Second)
	}
	login()
	if len(s.adminSessions) != 1 {
		t.Fatal("expired sessions not pruned")
	}
}
