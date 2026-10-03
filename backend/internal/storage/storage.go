// Package storage opens PostgreSQL and MinIO and initializes the database schema.
package storage

import (
	"context"
	"database/sql"
	_ "embed"
	"encoding/json"
	"errors"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"

	"anban/backend/internal/config"
)

//go:embed schema.sql
var schema string

var healthDefaults = map[string][]string{
	"stoolStatus":     {"正常", "未排便", "黑便", "血便", "便秘", "腹泻"},
	"urineStatus":     {"正常", "尿痛", "血尿"},
	"urineColor":      {"浅黄", "淡黄色，类似淡啤酒色"},
	"urineAppearance": {"清澈", "泡沫很少，静置一会泡沫消失", "泡沫很多"},
}

func Open(ctx context.Context, cfg config.Config) (*sql.DB, *minio.Client, error) {
	if cfg.DatabaseURL == "" || cfg.MinIOEndpoint == "" || cfg.MinIOAccessKey == "" || cfg.MinIOSecretKey == "" {
		return nil, nil, errors.New("DATABASE_URL and MINIO_ENDPOINT/ACCESS_KEY/SECRET_KEY are required")
	}
	db, err := sql.Open("pgx", cfg.DatabaseURL)
	if err != nil {
		return nil, nil, errors.New("invalid database configuration")
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
	if err = db.PingContext(ctx); err != nil {
		return nil, nil, errors.New("PostgreSQL connection failed; check DATABASE_URL")
	}
	_, err = db.ExecContext(ctx, schema)
	if err != nil {
		return nil, nil, errors.New("database schema initialization failed")
	}
	for key, options := range healthDefaults {
		raw, _ := json.Marshal(options)
		if _, err = db.ExecContext(ctx, `INSERT INTO anban_health_options(key,options) VALUES($1,$2) ON CONFLICT(key) DO NOTHING`, key, string(raw)); err != nil {
			return nil, nil, errors.New("health options initialization failed")
		}
	}
	objects, err := minio.New(cfg.MinIOEndpoint, &minio.Options{Creds: credentials.NewStaticV4(cfg.MinIOAccessKey, cfg.MinIOSecretKey, ""), Secure: cfg.MinIOSecure})
	if err != nil {
		return nil, nil, err
	}
	exists, err := objects.BucketExists(ctx, cfg.MinIOBucket)
	if err != nil || !exists {
		return nil, nil, errors.New("MinIO bucket unavailable; check S3 API endpoint and create private bucket")
	}
	ok = true
	return db, objects, nil
}
