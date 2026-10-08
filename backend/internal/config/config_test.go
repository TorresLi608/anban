package config

import (
	"strings"
	"testing"
)

func TestLoad(t *testing.T) {
	for _, key := range []string{"ANBAN_ADDR", "ANBAN_ORIGINS", "DATABASE_URL", "MINIO_ENDPOINT", "MINIO_ACCESS_KEY", "MINIO_SECRET_KEY", "MINIO_USE_SSL", "MINIO_BUCKET", "ANBAN_ANDROID_VERSION_CODE", "ANBAN_ANDROID_VERSION_NAME", "ANBAN_ANDROID_DOWNLOAD_URL", "ANBAN_ANDROID_RELEASE_NOTES", "ANBAN_ADMIN_USERNAME", "ANBAN_ADMIN_PASSWORD", "ANBAN_PUBLIC_URL"} {
		t.Setenv(key, "")
	}
	cfg := Load()
	if cfg.Addr != "127.0.0.1:8024" || cfg.MinIOBucket != "anban" || !cfg.MinIOSecure || cfg.AdminUsername != "admin" || cfg.AdminPassword != "" {
		t.Fatal("defaults changed")
	}
	t.Setenv("ANBAN_ADDR", ":9000")
	t.Setenv("DATABASE_URL", "postgres://test")
	t.Setenv("MINIO_ENDPOINT", "storage:9000")
	t.Setenv("MINIO_USE_SSL", "false")
	t.Setenv("ANBAN_ORIGINS", "https://a.test,https://b.test")
	cfg = Load()
	if cfg.Addr != ":9000" || cfg.DatabaseURL != "postgres://test" || cfg.MinIOEndpoint != "storage:9000" || cfg.MinIOSecure || len(cfg.Origins) != 2 {
		t.Fatal("environment overrides lost")
	}
}

func TestAdminCredentials(t *testing.T) {
	for _, tc := range []struct {
		username, password string
		valid              bool
	}{
		{"", "", true}, {"admin", "", true}, {"admin", "secret123", true},
		{"admin", "中文密码六个", true}, {"admin", strings.Repeat("a", 72), true},
		{"", "secret123", false}, {"ab", "secret123", false}, {"a,b", "secret123", false},
		{"admin", "12345", false}, {"admin", strings.Repeat("a", 73), false},
		{"admin", strings.Repeat("密", 25), false},
	} {
		cfg := Config{Addr: ":8024", AdminUsername: tc.username, AdminPassword: tc.password}
		if (cfg.Validate() == nil) != tc.valid {
			t.Fatalf("unexpected validation for username %q, password length %d", tc.username, len(tc.password))
		}
	}
	t.Setenv("ANBAN_ADMIN_USERNAME", " Custom_Admin ")
	t.Setenv("ANBAN_ADMIN_PASSWORD", "  secret$123  ")
	t.Setenv("ANBAN_ADMIN_USERS", "legacy_user")
	cfg := Load()
	if cfg.AdminUsername != "custom_admin" || cfg.AdminPassword != "  secret$123  " {
		t.Fatal("admin environment was not loaded correctly")
	}
}

func TestAndroidUpdateConfig(t *testing.T) {
	valid := Config{Addr: ":8024", AndroidVersionCode: "2", AndroidVersionName: "1.0.1", AndroidDownloadURL: "https://downloads.example.com/anban.apk", AndroidReleaseNotes: "修复问题"}
	if err := valid.Validate(); err != nil {
		t.Fatal(err)
	}
	for _, code := range []string{"", "0", "-1", "1.5", "abc", "2100000001"} {
		cfg := valid
		cfg.AndroidVersionCode = code
		if cfg.Validate() == nil {
			t.Fatalf("invalid version accepted: %q", code)
		}
	}
	for _, link := range []string{"", "http://example.com/a.apk", "https:///a.apk", "https://user:pass@example.com/a.apk", "intent://install"} {
		cfg := valid
		cfg.AndroidDownloadURL = link
		if cfg.Validate() == nil {
			t.Fatalf("invalid download URL accepted: %q", link)
		}
	}
	t.Setenv("ANBAN_ANDROID_VERSION_CODE", " 2 ")
	t.Setenv("ANBAN_ANDROID_VERSION_NAME", "1.0.1")
	t.Setenv("ANBAN_ANDROID_DOWNLOAD_URL", valid.AndroidDownloadURL)
	t.Setenv("ANBAN_ANDROID_RELEASE_NOTES", valid.AndroidReleaseNotes)
	cfg := Load()
	if cfg.AndroidVersionCode != valid.AndroidVersionCode || cfg.AndroidVersionName != valid.AndroidVersionName || cfg.AndroidDownloadURL != valid.AndroidDownloadURL || cfg.AndroidReleaseNotes != valid.AndroidReleaseNotes {
		t.Fatal("update environment not loaded")
	}
}

func TestListenAddress(t *testing.T) {
	for _, addr := range []string{"http://10.0.2.2:8024", "localhost", "localhost:99999", "localhost:nope"} {
		if (Config{Addr: addr}).Validate() == nil {
			t.Fatal("invalid listen address accepted")
		}
	}
	for _, addr := range []string{"127.0.0.1:8024", "0.0.0.0:8024", ":8024", "[::1]:8024"} {
		if err := (Config{Addr: addr}).Validate(); err != nil {
			t.Fatal(err)
		}
	}
}

func TestPublicDownloadOrigin(t *testing.T) {
	for _, origin := range []string{"http://api.example.com", "https://user:pass@api.example.com", "https://api.example.com/path", "https://api.example.com?x=1", "https://api.example.com#fragment"} {
		if (Config{Addr: ":8024", PublicURL: origin}).Validate() == nil {
			t.Fatalf("invalid public origin accepted: %s", origin)
		}
	}
	if err := (Config{Addr: ":8024", PublicURL: "https://api.example.com"}).Validate(); err != nil {
		t.Fatal(err)
	}
}
