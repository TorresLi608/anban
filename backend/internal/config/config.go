// Package config reads backend settings from the environment.
package config

import (
	"errors"
	"net"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Addr           string
	Origins        []string
	DatabaseURL    string
	MinIOEndpoint  string
	MinIOAccessKey string
	MinIOSecretKey string
	MinIOSecure    bool
	MinIOBucket    string
}

func Load() Config {
	return Config{
		Addr:           env("ANBAN_ADDR", "127.0.0.1:8024"),
		Origins:        strings.Split(os.Getenv("ANBAN_ORIGINS"), ","),
		DatabaseURL:    os.Getenv("DATABASE_URL"),
		MinIOEndpoint:  os.Getenv("MINIO_ENDPOINT"),
		MinIOAccessKey: os.Getenv("MINIO_ACCESS_KEY"),
		MinIOSecretKey: os.Getenv("MINIO_SECRET_KEY"),
		MinIOSecure:    env("MINIO_USE_SSL", "true") == "true",
		MinIOBucket:    env("MINIO_BUCKET", "anban"),
	}
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// Validate rejects client URLs before attempting any database connection.
func (c Config) Validate() error {
	host, port, err := net.SplitHostPort(c.Addr)
	n, numberErr := strconv.Atoi(port)
	if err != nil || strings.ContainsAny(host, "/?#") || numberErr != nil || n < 0 || n > 65535 {
		return errors.New("ANBAN_ADDR 必须是 host:port（例如 127.0.0.1:8024），不能包含 http://；客户端完整地址请填写 ANBAN_API_URL")
	}
	return nil
}
