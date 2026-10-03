// Package config reads backend settings from the environment.
package config

import (
	"errors"
	"net"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
)

type Config struct {
	Addr                string
	Origins             []string
	DatabaseURL         string
	MinIOEndpoint       string
	MinIOAccessKey      string
	MinIOSecretKey      string
	MinIOSecure         bool
	MinIOBucket         string
	AndroidVersionCode  string
	AndroidVersionName  string
	AndroidDownloadURL  string
	AndroidReleaseNotes string
	AdminUsers          []string
	PublicURL           string
}

func Load() Config {
	return Config{
		Addr:                env("ANBAN_ADDR", "127.0.0.1:8024"),
		Origins:             strings.Split(os.Getenv("ANBAN_ORIGINS"), ","),
		DatabaseURL:         os.Getenv("DATABASE_URL"),
		MinIOEndpoint:       os.Getenv("MINIO_ENDPOINT"),
		MinIOAccessKey:      os.Getenv("MINIO_ACCESS_KEY"),
		MinIOSecretKey:      os.Getenv("MINIO_SECRET_KEY"),
		MinIOSecure:         env("MINIO_USE_SSL", "true") == "true",
		MinIOBucket:         env("MINIO_BUCKET", "anban"),
		AndroidVersionCode:  strings.TrimSpace(os.Getenv("ANBAN_ANDROID_VERSION_CODE")),
		AndroidVersionName:  strings.TrimSpace(os.Getenv("ANBAN_ANDROID_VERSION_NAME")),
		AndroidDownloadURL:  strings.TrimSpace(os.Getenv("ANBAN_ANDROID_DOWNLOAD_URL")),
		AndroidReleaseNotes: strings.TrimSpace(os.Getenv("ANBAN_ANDROID_RELEASE_NOTES")),
		AdminUsers:          strings.Split(strings.ToLower(os.Getenv("ANBAN_ADMIN_USERS")), ","),
		PublicURL:           strings.TrimRight(strings.TrimSpace(os.Getenv("ANBAN_PUBLIC_URL")), "/"),
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
	for _, username := range c.AdminUsers {
		if name := strings.TrimSpace(username); name != "" && !regexp.MustCompile(`^[a-z0-9_]{3,32}$`).MatchString(name) {
			return errors.New("ANBAN_ADMIN_USERS 应为已注册账号，以英文逗号分隔")
		}
	}
	if c.PublicURL != "" {
		u, err := url.Parse(c.PublicURL)
		if err != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
			return errors.New("ANBAN_PUBLIC_URL 必须是公开可访问的 HTTPS 后端域名，不含路径、查询参数或账号密码")
		}
	}
	if release := c.InitialAndroidRelease(); release != nil {
		return release.Validate()
	}
	return nil
}

type AndroidRelease struct {
	VersionCode  int    `json:"versionCode"`
	VersionName  string `json:"versionName"`
	DownloadURL  string `json:"downloadUrl"`
	ReleaseNotes string `json:"releaseNotes"`
}

func (r AndroidRelease) Validate() error {
	if r.VersionCode < 1 || r.VersionCode > 2100000000 || strings.TrimSpace(r.VersionName) == "" || len(r.VersionName) > 64 || len(r.ReleaseNotes) > 4000 {
		return errors.New("版本编号须为 1–2100000000；版本名称不能为空且最多 64 字节；更新说明最多 4000 字节")
	}
	u, err := url.Parse(r.DownloadURL)
	if err != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil {
		return errors.New("下载地址必须是无账号密码的 HTTPS 链接")
	}
	return nil
}

// Environment values seed a new database once; subsequent edits live in the admin UI.
func (c Config) InitialAndroidRelease() *AndroidRelease {
	if c.AndroidVersionCode == "" && c.AndroidVersionName == "" && c.AndroidDownloadURL == "" && c.AndroidReleaseNotes == "" {
		return nil
	}
	code, _ := strconv.Atoi(c.AndroidVersionCode)
	return &AndroidRelease{code, c.AndroidVersionName, c.AndroidDownloadURL, c.AndroidReleaseNotes}
}
