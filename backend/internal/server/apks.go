package server

import (
	"archive/zip"
	"context"
	"database/sql"
	"errors"
	"mime/multipart"
	"net/http"
	"strings"
	"time"

	"github.com/minio/minio-go/v7"
)

const maxAPKSize = 300 << 20

func (c *Server) uploadAPK(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		fail(w, 405, "method not allowed")
		return
	}
	if c.publicURL == "" {
		fail(w, 503, "安装包上传尚未配置下载域名，请先设置 ANBAN_PUBLIC_URL")
		return
	}
	_ = http.NewResponseController(w).SetReadDeadline(time.Now().Add(10 * time.Minute))
	_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(10 * time.Minute))
	r.Body = http.MaxBytesReader(w, r.Body, maxAPKSize+(1<<20))
	if err := r.ParseMultipartForm(8 << 20); err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) || errors.Is(err, multipart.ErrMessageTooLarge) {
			fail(w, 413, "安装包不能超过 300 MB")
		} else {
			fail(w, 400, "无法读取安装包，请重新选择文件")
		}
		return
	}
	defer r.MultipartForm.RemoveAll()
	files := r.MultipartForm.File["file"]
	if len(files) != 1 || len(r.MultipartForm.File) != 1 {
		fail(w, 400, "请选择一个 APK 文件")
		return
	}
	header := files[0]
	if !strings.HasSuffix(strings.ToLower(header.Filename), ".apk") || header.Size <= 0 {
		fail(w, 400, "请选择有效的 .apk 安装包")
		return
	}
	if header.Size > maxAPKSize {
		fail(w, 413, "安装包不能超过 300 MB")
		return
	}
	file, err := header.Open()
	if err != nil {
		fail(w, 500, "读取安装包失败")
		return
	}
	defer file.Close()
	archive, err := zip.NewReader(file, header.Size)
	manifest := false
	if err == nil {
		for _, entry := range archive.File {
			if entry.Name == "AndroidManifest.xml" && !entry.FileInfo().IsDir() {
				manifest = true
				break
			}
		}
	}
	if !manifest {
		fail(w, 400, "文件不是有效的 Android APK 安装包")
		return
	}
	id := randomID()
	key := "releases/android/" + id + ".apk"
	_, err = c.objects.PutObject(r.Context(), c.bucket, key, file, header.Size, minio.PutObjectOptions{ContentType: "application/vnd.android.package-archive"})
	if err != nil {
		fail(w, 503, "安装包上传失败，请稍后重试")
		return
	}
	if _, err = c.db.ExecContext(r.Context(), `INSERT INTO anban_apks(id,size) VALUES($1,$2)`, id, header.Size); err != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = c.objects.RemoveObject(ctx, c.bucket, key, minio.RemoveObjectOptions{})
		fail(w, 503, "安装包保存失败，请重新上传")
		return
	}
	writeJSON(w, 200, map[string]any{"id": id, "size": header.Size, "downloadUrl": c.publicURL + "/api/v1/app/android-apk/" + id + ".apk"})
}

func (c *Server) downloadAPK(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" && r.Method != "HEAD" {
		fail(w, 405, "method not allowed")
		return
	}
	_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(10 * time.Minute))
	filename := strings.TrimPrefix(r.URL.Path, "/api/v1/app/android-apk/")
	id := strings.TrimSuffix(filename, ".apk")
	if !strings.HasSuffix(filename, ".apk") || !filePattern.MatchString(id) {
		fail(w, 404, "安装包不存在")
		return
	}
	var created time.Time
	err := c.db.QueryRowContext(r.Context(), `SELECT created_at FROM anban_apks WHERE id=$1`, id).Scan(&created)
	if err == sql.ErrNoRows {
		fail(w, 404, "安装包不存在")
		return
	}
	if err != nil {
		fail(w, 503, "下载暂不可用")
		return
	}
	object, err := c.objects.GetObject(r.Context(), c.bucket, "releases/android/"+id+".apk", minio.GetObjectOptions{})
	if err != nil {
		fail(w, 503, "下载暂不可用")
		return
	}
	defer object.Close()
	if _, err = object.Stat(); err != nil {
		fail(w, 503, "安装包读取失败，请稍后重试")
		return
	}
	w.Header().Set("Content-Type", "application/vnd.android.package-archive")
	w.Header().Set("Content-Disposition", `attachment; filename="anban.apk"`)
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	w.Header().Set("ETag", `"`+id+`"`)
	http.ServeContent(w, r, "anban.apk", created, object)
}
