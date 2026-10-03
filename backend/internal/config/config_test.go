package config

import "testing"

func TestLoad(t *testing.T) {
	for _, key := range []string{"ANBAN_ADDR", "ANBAN_ORIGINS", "DATABASE_URL", "MINIO_ENDPOINT", "MINIO_ACCESS_KEY", "MINIO_SECRET_KEY", "MINIO_USE_SSL", "MINIO_BUCKET", "ANBAN_ANDROID_VERSION_CODE", "ANBAN_ANDROID_VERSION_NAME", "ANBAN_ANDROID_DOWNLOAD_URL", "ANBAN_ANDROID_RELEASE_NOTES"} {
		t.Setenv(key, "")
	}
	cfg := Load()
	if cfg.Addr != "127.0.0.1:8024" || cfg.MinIOBucket != "anban" || !cfg.MinIOSecure {
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
