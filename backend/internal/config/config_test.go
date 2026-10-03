package config

import "testing"

func TestLoad(t *testing.T) {
	for _, key := range []string{"ANBAN_ADDR", "ANBAN_ORIGINS", "DATABASE_URL", "MINIO_ENDPOINT", "MINIO_ACCESS_KEY", "MINIO_SECRET_KEY", "MINIO_USE_SSL", "MINIO_BUCKET"} {
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
