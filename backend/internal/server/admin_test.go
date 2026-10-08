package server

import (
	"archive/zip"
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"mime/multipart"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/minio/minio-go/v7"

	"anban/backend/internal/config"
)

// Uses only a newly created schema; never reads or writes the application's records.
func TestAdminIntegration(t *testing.T) {
	if os.Getenv("ANBAN_ADMIN_INTEGRATION") != "1" {
		t.Skip("set ANBAN_ADMIN_INTEGRATION=1 with service environment")
	}
	cfg := config.Load()
	base, err := sql.Open("pgx", cfg.DatabaseURL)
	if err != nil {
		t.Fatal("test database configuration is invalid")
	}
	defer base.Close()
	schema := "anban_admin_test_" + randomID()[:16]
	if _, err = base.Exec(`CREATE SCHEMA ` + schema); err != nil {
		t.Fatal(err)
	}
	defer func() {
		if _, err := base.Exec(`DROP SCHEMA ` + schema + ` CASCADE`); err != nil {
			t.Error(err)
		}
	}()
	u, err := url.Parse(cfg.DatabaseURL)
	if err != nil {
		t.Fatal("test database URL is invalid")
	}
	query := u.Query()
	query.Set("search_path", schema)
	u.RawQuery = query.Encode()
	cfg.DatabaseURL = u.String()
	cfg.AdminUsername, cfg.AdminPassword = "admin_test", randomID()
	cfg.PublicURL = "https://downloads.example.test"
	cfg.AndroidVersionCode, cfg.AndroidVersionName, cfg.AndroidDownloadURL, cfg.AndroidReleaseNotes = "", "", "", ""
	s, err := New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if s == nil {
			return
		}
		rows, err := s.db.Query(`SELECT id FROM anban_apks`)
		if err == nil {
			var ids []string
			for rows.Next() {
				var id string
				if rows.Scan(&id) == nil {
					ids = append(ids, id)
				}
			}
			rows.Close()
			for _, id := range ids {
				if err := s.objects.RemoveObject(context.Background(), s.bucket, "releases/android/"+id+".apk", minio.RemoveObjectOptions{}); err != nil {
					t.Error(err)
				}
			}
		}
		s.Close()
	}()
	request := func(method, path, token string, body any) *httptest.ResponseRecorder {
		raw, _ := json.Marshal(body)
		r := httptest.NewRequest(method, path, bytes.NewReader(raw))
		if token != "" {
			r.Header.Set("Authorization", "Bearer "+token)
		}
		w := httptest.NewRecorder()
		s.ServeHTTP(w, r)
		return w
	}
	read := func(w *httptest.ResponseRecorder, target any) {
		t.Helper()
		if w.Code != 200 {
			t.Fatalf("status %d: %s", w.Code, w.Body)
		}
		if err := json.Unmarshal(w.Body.Bytes(), target); err != nil {
			t.Fatal(err)
		}
	}
	creds := map[string]string{"username": cfg.AdminUsername, "password": cfg.AdminPassword}
	mobileCreds := map[string]string{"username": cfg.AdminUsername, "password": randomID()}
	var registered map[string]any
	read(request("POST", "/api/v1/auth/register", "", mobileCreds), &registered)
	var ordinary map[string]any
	read(request("POST", "/api/v1/auth/register", "", map[string]string{"username": "ordinary_test", "password": creds["password"]}), &ordinary)
	s.Close()
	s, err = New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"me", "android-release", "health-options"} {
		if request("GET", "/api/v1/admin/"+path, ordinary["token"].(string), nil).Code != 401 {
			t.Fatal("ordinary user reached admin API")
		}
		if request("PUT", "/api/v1/admin/"+path, ordinary["token"].(string), nil).Code != 401 {
			t.Fatal("ordinary user wrote admin API")
		}
	}
	if request("POST", "/api/v1/admin/login", "", map[string]string{"username": "ordinary_test", "password": creds["password"]}).Code != 401 {
		t.Fatal("ordinary user logged into admin")
	}
	if request("POST", "/api/v1/admin/login", "", map[string]string{"username": creds["username"], "password": "wrongpassword"}).Code != 401 {
		t.Fatal("wrong password accepted")
	}
	var session map[string]any
	read(request("POST", "/api/v1/admin/login", "", creds), &session)
	token := session["token"].(string)
	if request("GET", "/api/v1/admin/me", registered["token"].(string), nil).Code != 401 {
		t.Fatal("same-name App user reached admin API")
	}
	if request("POST", "/api/v1/admin/login", "", mobileCreds).Code != 401 {
		t.Fatal("App password accepted by admin login")
	}
	for _, path := range []string{"/api/v1/auth/me", "/api/v1/vault", "/api/v1/files"} {
		if request("GET", path, token, nil).Code != 401 {
			t.Fatal("admin token accessed App data")
		}
	}

	var apk bytes.Buffer
	archive := zip.NewWriter(&apk)
	entry, _ := archive.Create("AndroidManifest.xml")
	_, _ = entry.Write([]byte("synthetic APK fixture; never install"))
	archive.Close()
	upload := func(token, name string, contents []byte) *httptest.ResponseRecorder {
		var body bytes.Buffer
		form := multipart.NewWriter(&body)
		file, _ := form.CreateFormFile("file", name)
		_, _ = file.Write(contents)
		form.Close()
		r := httptest.NewRequest("POST", "/api/v1/admin/apks", &body)
		r.Header.Set("Content-Type", form.FormDataContentType())
		if token != "" {
			r.Header.Set("Authorization", "Bearer "+token)
		}
		w := httptest.NewRecorder()
		s.ServeHTTP(w, r)
		return w
	}
	if upload("", "anban.apk", apk.Bytes()).Code != 401 || upload(ordinary["token"].(string), "anban.apk", apk.Bytes()).Code != 401 {
		t.Fatal("unauthorized APK upload accepted")
	}
	if upload(token, "anban.txt", apk.Bytes()).Code != 400 || upload(token, "anban.apk", []byte("not an APK")).Code != 400 {
		t.Fatal("invalid APK accepted")
	}
	var uploaded struct {
		ID          string `json:"id"`
		Size        int64  `json:"size"`
		DownloadURL string `json:"downloadUrl"`
	}
	read(upload(token, "anban.apk", apk.Bytes()), &uploaded)
	if !strings.HasPrefix(uploaded.DownloadURL, cfg.PublicURL+"/api/v1/app/android-apk/") || uploaded.Size != int64(apk.Len()) {
		t.Fatal("invalid generated download URL")
	}
	path := "/api/v1/app/android-apk/" + uploaded.ID + ".apk"
	download := request("GET", path, "", nil)
	if download.Code != 200 || !bytes.Equal(download.Body.Bytes(), apk.Bytes()) || download.Header().Get("Content-Disposition") != `attachment; filename="anban.apk"` {
		t.Fatal("public APK download does not match upload")
	}
	rangeRequest := httptest.NewRequest("GET", path, nil)
	rangeRequest.Header.Set("Range", "bytes=0-3")
	ranged := httptest.NewRecorder()
	s.ServeHTTP(ranged, rangeRequest)
	if ranged.Code != 206 || !bytes.Equal(ranged.Body.Bytes(), apk.Bytes()[:4]) {
		t.Fatal("APK range requests do not work")
	}
	expires, _ := time.Parse(time.RFC3339Nano, session["expiresAt"].(string))
	if time.Until(expires) > 8*time.Hour || time.Until(expires) < 7*time.Hour {
		t.Fatal("unexpected admin session duration")
	}
	if request("GET", "/api/v1/app/android-update", "", nil).Code != 204 {
		t.Fatal("empty release must be disabled")
	}
	var initial releaseState
	read(request("GET", "/api/v1/admin/android-release", token, nil), &initial)
	release := config.AndroidRelease{VersionCode: 2, VersionName: "1.0.1", DownloadURL: uploaded.DownloadURL, ReleaseNotes: "修复问题"}
	payload := map[string]any{"revision": initial.Revision, "enabled": true, "release": release}
	var saved releaseState
	read(request("PUT", "/api/v1/admin/android-release", token, payload), &saved)
	var public config.AndroidRelease
	read(request("GET", "/api/v1/app/android-update", "", nil), &public)
	if public != release {
		t.Fatal("published release not visible to Android")
	}
	if request("PUT", "/api/v1/admin/android-release", token, payload).Code != 409 {
		t.Fatal("stale release overwrite accepted")
	}
	payload["revision"], payload["enabled"] = saved.Revision, false
	read(request("PUT", "/api/v1/admin/android-release", token, payload), &saved)
	if request("GET", "/api/v1/app/android-update", "", nil).Code != 204 {
		t.Fatal("disabled update still public")
	}
	payload["revision"] = saved.Revision
	release.VersionCode = 1
	payload["release"] = release
	if request("PUT", "/api/v1/admin/android-release", token, payload).Code != 400 {
		t.Fatal("version downgrade accepted")
	}
	release.VersionCode = 3
	release.DownloadURL = "http://example.com/unsafe.apk"
	payload["release"] = release
	if request("PUT", "/api/v1/admin/android-release", token, payload).Code != 400 {
		t.Fatal("unsafe download accepted")
	}
	var health healthState
	read(request("GET", "/api/v1/admin/health-options", token, nil), &health)
	stale := health.Revision
	health.Options["stoolStatus"] = []string{"正常", "测试新增"}
	var healthSaved healthState
	read(request("PUT", "/api/v1/admin/health-options", token, health), &healthSaved)
	if request("PUT", "/api/v1/admin/health-options", token, health).Code != 409 {
		t.Fatal("stale health overwrite accepted")
	}
	if healthSaved.Revision == stale {
		t.Fatal("health revision not updated")
	}
	var mobile map[string][]string
	read(request("GET", "/api/v1/config/health-options", ordinary["token"].(string), nil), &mobile)
	if strings.Join(mobile["stoolStatus"], ",") != "正常,测试新增" {
		t.Fatal("mobile health options not updated")
	}
	healthSaved.Options["urineStatus"] = []string{"重复", "重复"}
	if request("PUT", "/api/v1/admin/health-options", token, healthSaved).Code != 400 {
		t.Fatal("duplicate health options accepted")
	}
	// A second server initialization must preserve admin edits over environment defaults.
	s.Close()
	cfg.AndroidVersionCode, cfg.AndroidVersionName, cfg.AndroidDownloadURL = "99", "9.9.9", "https://example.com/old-env.apk"
	s, err = New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if request("GET", "/api/v1/admin/me", token, nil).Code != 401 {
		t.Fatal("restart retained admin session")
	}
	read(request("POST", "/api/v1/admin/login", "", creds), &session)
	token = session["token"].(string)
	var reopened releaseState
	read(request("GET", "/api/v1/admin/android-release", token, nil), &reopened)
	if reopened.Revision != saved.Revision || reopened.Enabled || reopened.Release.VersionCode != 2 {
		t.Fatal("restart overwrote published state")
	}
	// Environment credential changes revoke only admin sessions and never mutate App accounts.
	s.Close()
	cfg.AdminUsername, cfg.AdminPassword = "operator_next", randomID()
	s, err = New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if request("GET", "/api/v1/admin/me", token, nil).Code != 401 {
		t.Fatal("credential change retained old admin session")
	}
	for _, appToken := range []string{registered["token"].(string), ordinary["token"].(string)} {
		if request("GET", "/api/v1/auth/me", appToken, nil).Code != 200 {
			t.Fatal("admin credential change revoked an App session")
		}
	}
	if request("POST", "/api/v1/admin/login", "", creds).Code != 401 {
		t.Fatal("old admin credentials still work")
	}
	creds["username"], creds["password"] = cfg.AdminUsername, cfg.AdminPassword
	read(request("POST", "/api/v1/admin/login", "", creds), &session)
	token = session["token"].(string)
	if request("POST", "/api/v1/auth/login", "", creds).Code != 401 {
		t.Fatal("admin environment credentials created an App account")
	}
	read(request("POST", "/api/v1/auth/login", "", mobileCreds), &registered)
	if request("POST", "/api/v1/admin/password", token, map[string]string{"currentPassword": cfg.AdminPassword, "newPassword": "unwanted-change"}).Code != 404 {
		t.Fatal("retired password endpoint is still active")
	}
	read(request("POST", "/api/v1/admin/logout", token, nil), &registered)
	if request("GET", "/api/v1/admin/me", token, nil).Code != 401 {
		t.Fatal("logout did not revoke admin session")
	}
	// Optional browser QA uses this same isolated, disposable backend.
	if fixture := os.Getenv("ANBAN_ADMIN_PREVIEW_FILE"); fixture != "" {
		httpServer := httptest.NewServer(s)
		defer httpServer.Close()
		apkPath := fixture + ".apk"
		if err := os.WriteFile(apkPath, apk.Bytes(), 0600); err != nil {
			t.Fatal(err)
		}
		defer os.Remove(apkPath)
		raw, _ := json.Marshal(map[string]string{"url": httpServer.URL, "username": creds["username"], "password": creds["password"], "apkPath": apkPath})
		if err := os.WriteFile(fixture, raw, 0600); err != nil {
			t.Fatal(err)
		}
		defer os.Remove(fixture)
		t.Log("Isolated admin preview ready")
		for i := 0; i < 1800; i++ {
			if _, err := os.Stat(fixture + ".stop"); err == nil {
				os.Remove(fixture + ".stop")
				return
			}
			time.Sleep(time.Second)
		}
		t.Fatal("preview timed out")
	}
}
