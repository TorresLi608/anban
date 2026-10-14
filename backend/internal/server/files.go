package server

import (
	"bytes"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path/filepath"
	"strings"

	"github.com/minio/minio-go/v7"
)

const maxFile = 40 << 20 // 40 MB attachment.

func detectContentType(filename string, data []byte) string {
	ext := strings.ToLower(filepath.Ext(filename))
	switch ext {
	case ".pdf":
		return "application/pdf"
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".png":
		return "image/png"
	case ".webp":
		return "image/webp"
	case ".gif":
		return "image/gif"
	case ".mp4":
		return "video/mp4"
	case ".mov":
		return "video/quicktime"
	case ".mp3":
		return "audio/mpeg"
	case ".m4a":
		return "audio/mp4"
	case ".wav":
		return "audio/wav"
	case ".txt":
		return "text/plain; charset=utf-8"
	}
	if len(data) > 0 {
		ct := http.DetectContentType(data)
		if ct != "application/octet-stream" {
			return ct
		}
	}
	return "application/octet-stream"
}

func sanitizeFilename(name string) string {
	name = filepath.Base(strings.TrimSpace(name))
	name = strings.ReplaceAll(name, "/", "_")
	name = strings.ReplaceAll(name, "\\", "_")
	if name == "." || name == "" {
		return "file.bin"
	}
	return name
}

type fileUploadRequest struct {
	File        string `json:"file"`
	Filename    string `json:"filename"`
	ContentType string `json:"contentType"`
	Size        int64  `json:"size"`
}

func (c *Server) file(w http.ResponseWriter, r *http.Request, user string) {
	if r.URL.Path == "/api/v1/files" && r.Method == "POST" {
		c.uploadFile(w, r, user)
		return
	}

	sub := strings.TrimPrefix(r.URL.Path, "/api/v1/files/")
	parts := strings.Split(sub, "/")
	id := parts[0]
	if !filePattern.MatchString(id) {
		fail(w, 404, "附件不存在")
		return
	}

	if len(parts) == 1 {
		switch r.Method {
		case "GET":
			c.downloadOrReadFile(w, r, user, id, false)
		case "DELETE":
			c.deleteFile(w, r, user, id)
		case "PUT", "PATCH":
			c.renameFile(w, r, user, id)
		default:
			fail(w, 405, "method not allowed")
		}
		return
	}

	action := parts[1]
	switch action {
	case "raw":
		if r.Method == "GET" {
			c.downloadOrReadFile(w, r, user, id, true)
		} else {
			fail(w, 405, "method not allowed")
		}
	case "share":
		if r.Method == "POST" {
			c.createShare(w, r, user, id)
		} else {
			fail(w, 405, "method not allowed")
		}
	case "rename":
		if r.Method == "PUT" || r.Method == "POST" {
			c.renameFile(w, r, user, id)
		} else {
			fail(w, 405, "method not allowed")
		}
	default:
		fail(w, 404, "not found")
	}
}

func (c *Server) uploadFile(w http.ResponseWriter, r *http.Request, user string) {
	var body json.RawMessage
	if !decode(w, r, &body, maxFile) {
		return
	}
	if len(body) == 0 {
		fail(w, 400, "invalid file payload")
		return
	}

	var req fileUploadRequest
	id := randomID()

	// 检查是否包含 file 字段（base64 编码的明文字节）
	if err := json.Unmarshal(body, &req); err == nil && req.File != "" {
		data, err := base64.StdEncoding.DecodeString(req.File)
		if err != nil {
			data, err = base64.RawStdEncoding.DecodeString(req.File)
		}
		if err != nil {
			fail(w, 400, "附件内容不是合法的 base64 数据")
			return
		}

		filename := sanitizeFilename(req.Filename)
		contentType := req.ContentType
		if contentType == "" {
			contentType = detectContentType(filename, data)
		}

		// MinIO 对象 key 包含文件名与扩展名，例如：user/id/文件名.pdf
		key := user + "/" + id + "/" + filename
		putOpts := minio.PutObjectOptions{
			ContentType:        contentType,
			ContentDisposition: fmt.Sprintf("inline; filename=%q", filename),
		}

		if _, err := c.objects.PutObject(r.Context(), c.bucket, key, bytes.NewReader(data), int64(len(data)), putOpts); err != nil {
			fail(w, 502, "附件上传失败")
			return
		}

		if _, err := c.db.ExecContext(r.Context(),
			`INSERT INTO anban_files(id, user_id, filename, content_type, size, minio_key) VALUES($1, $2, $3, $4, $5, $6)`,
			id, user, filename, contentType, int64(len(data)), key); err != nil {
			_ = c.objects.RemoveObject(r.Context(), c.bucket, key, minio.RemoveObjectOptions{})
			fail(w, 500, "附件索引保存失败")
			return
		}

		writeJSON(w, 200, map[string]any{
			"id":          id,
			"filename":    filename,
			"contentType": contentType,
			"size":        len(data),
		})
		return
	}

	// 兼容任意原始 JSON 载荷
	key := user + "/" + id
	if _, err := c.objects.PutObject(r.Context(), c.bucket, key, bytes.NewReader(body), int64(len(body)), minio.PutObjectOptions{ContentType: "application/json"}); err != nil {
		fail(w, 502, "附件上传失败")
		return
	}
	if _, err := c.db.ExecContext(r.Context(), `INSERT INTO anban_files(id, user_id, minio_key) VALUES($1, $2, $3)`, id, user, key); err != nil {
		_ = c.objects.RemoveObject(r.Context(), c.bucket, key, minio.RemoveObjectOptions{})
		fail(w, 500, "附件索引保存失败")
		return
	}
	writeJSON(w, 200, map[string]string{"id": id})
}

func (c *Server) downloadOrReadFile(w http.ResponseWriter, r *http.Request, user, id string, forceRaw bool) {
	var filename, contentType, minioKey string
	var size int64
	err := c.db.QueryRowContext(r.Context(),
		`SELECT filename, content_type, size, minio_key FROM anban_files WHERE id=$1 AND user_id=$2`,
		id, user).Scan(&filename, &contentType, &size, &minioKey)
	if err != nil {
		if err == sql.ErrNoRows {
			fail(w, 404, "附件不存在")
		} else {
			fail(w, 503, "附件索引不可用")
		}
		return
	}

	if minioKey == "" {
		minioKey = user + "/" + id
	}

	object, err := c.objects.GetObject(r.Context(), c.bucket, minioKey, minio.GetObjectOptions{})
	if err != nil {
		fail(w, 502, "附件读取失败")
		return
	}
	defer object.Close()

	b, err := io.ReadAll(io.LimitReader(object, maxFile+1))
	if err != nil || len(b) > maxFile {
		fail(w, 502, "附件读取失败")
		return
	}

	if contentType == "" {
		contentType = detectContentType(filename, b)
	}
	if filename == "" {
		filename = id + ".bin"
	}

	// 强制以原始二进制流输出（预览/下载）
	if forceRaw || r.URL.Query().Get("raw") == "1" || r.URL.Query().Get("download") == "1" {
		// 如果存储的是包含 file 的 JSON，先还原
		rawBytes := extractRawBytes(b)
		w.Header().Set("Content-Type", contentType)
		disposition := "inline"
		if r.URL.Query().Get("download") == "1" {
			disposition = "attachment"
		}
		w.Header().Set("Content-Disposition", fmt.Sprintf("%s; filename*=UTF-8''%s", disposition, url.PathEscape(filename)))
		w.Write(rawBytes)
		return
	}

	// 如果读出的内容本来就是 JSON 格式（如旧加密或旧封装），直接返回
	var checkMap map[string]any
	if json.Unmarshal(b, &checkMap) == nil && (checkMap["file"] != nil || checkMap["ciphertext"] != nil) {
		w.Header().Set("Content-Type", "application/json")
		w.Write(b)
		return
	}

	// 否则封装为 JSON 返回给 App
	writeJSON(w, 200, map[string]any{
		"id":          id,
		"file":        base64.StdEncoding.EncodeToString(b),
		"filename":    filename,
		"contentType": contentType,
		"size":        len(b),
	})
}

func (c *Server) deleteFile(w http.ResponseWriter, r *http.Request, user, id string) {
	var minioKey string
	err := c.db.QueryRowContext(r.Context(), `SELECT minio_key FROM anban_files WHERE id=$1 AND user_id=$2`, id, user).Scan(&minioKey)
	if err != nil {
		if err == sql.ErrNoRows {
			fail(w, 404, "附件不存在")
		} else {
			fail(w, 503, "附件索引不可用")
		}
		return
	}

	// 从 MinIO 删除对象，彻底删除源文件释放存储空间
	if minioKey != "" {
		_ = c.objects.RemoveObject(r.Context(), c.bucket, minioKey, minio.RemoveObjectOptions{})
	}
	_ = c.objects.RemoveObject(r.Context(), c.bucket, user+"/"+id, minio.RemoveObjectOptions{})

	// 从数据库中删除记录
	if _, err := c.db.ExecContext(r.Context(), `DELETE FROM anban_files WHERE id=$1 AND user_id=$2`, id, user); err != nil {
		fail(w, 500, "删除附件索引失败")
		return
	}

	writeJSON(w, 200, map[string]any{"ok": true, "id": id})
}

func (c *Server) renameFile(w http.ResponseWriter, r *http.Request, user, id string) {
	var body struct {
		Filename string `json:"filename"`
	}
	if !decode(w, r, &body, 1<<16) {
		return
	}
	name := sanitizeFilename(body.Filename)
	if name == "" || name == "file.bin" {
		fail(w, 400, "无效的文件名称")
		return
	}

	contentType := detectContentType(name, nil)

	res, err := c.db.ExecContext(r.Context(),
		`UPDATE anban_files SET filename=$1, content_type=$2 WHERE id=$3 AND user_id=$4`,
		name, contentType, id, user)
	if err != nil {
		fail(w, 500, "修改文件名称失败")
		return
	}
	rows, _ := res.RowsAffected()
	if rows == 0 {
		fail(w, 404, "附件不存在")
		return
	}

	writeJSON(w, 200, map[string]any{
		"ok":          true,
		"id":          id,
		"filename":    name,
		"contentType": contentType,
	})
}

func (c *Server) createShare(w http.ResponseWriter, r *http.Request, user, id string) {
	var filename string
	err := c.db.QueryRowContext(r.Context(), `SELECT filename FROM anban_files WHERE id=$1 AND user_id=$2`, id, user).Scan(&filename)
	if err != nil {
		if err == sql.ErrNoRows {
			fail(w, 404, "附件不存在")
		} else {
			fail(w, 503, "附件索引不可用")
		}
		return
	}

	token := randomID()
	if _, err := c.db.ExecContext(r.Context(),
		`INSERT INTO anban_file_shares(token, file_id, user_id) VALUES($1, $2, $3)`,
		token, id, user); err != nil {
		fail(w, 500, "生成分享链接失败")
		return
	}

	baseURL := c.publicURL
	if baseURL == "" {
		scheme := "https"
		if r.TLS == nil && !strings.Contains(r.Header.Get("X-Forwarded-Proto"), "https") {
			scheme = "http"
		}
		baseURL = scheme + "://" + r.Host
	}
	shareURL := baseURL + "/api/v1/share/" + token

	writeJSON(w, 200, map[string]any{
		"ok":       true,
		"token":    token,
		"url":      shareURL,
		"filename": filename,
	})
}

func (c *Server) publicShare(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" && r.Method != "HEAD" {
		fail(w, 405, "method not allowed")
		return
	}
	token := strings.TrimPrefix(r.URL.Path, "/api/v1/share/")
	if !filePattern.MatchString(token) {
		fail(w, 404, "分享链接不存在或已失效")
		return
	}

	var fileID, userID, filename, contentType, minioKey string
	err := c.db.QueryRowContext(r.Context(),
		`SELECT f.id, f.user_id, f.filename, f.content_type, f.minio_key
		 FROM anban_file_shares s
		 JOIN anban_files f ON f.id = s.file_id
		 WHERE s.token = $1`, token).Scan(&fileID, &userID, &filename, &contentType, &minioKey)
	if err != nil {
		if err == sql.ErrNoRows {
			fail(w, 404, "分享链接不存在或已失效")
		} else {
			fail(w, 503, "分享服务暂不可用")
		}
		return
	}

	if minioKey == "" {
		minioKey = userID + "/" + fileID
	}

	object, err := c.objects.GetObject(r.Context(), c.bucket, minioKey, minio.GetObjectOptions{})
	if err != nil {
		fail(w, 502, "无法获取分享文件")
		return
	}
	defer object.Close()

	b, err := io.ReadAll(io.LimitReader(object, maxFile+1))
	if err != nil || len(b) > maxFile {
		fail(w, 502, "读取分享文件失败")
		return
	}

	rawBytes := extractRawBytes(b)
	if contentType == "" {
		contentType = detectContentType(filename, rawBytes)
	}
	if filename == "" {
		filename = "document" + filepath.Ext(filename)
		if filename == "document" {
			filename = "document.bin"
		}
	}

	disposition := "inline"
	if r.URL.Query().Get("download") == "1" {
		disposition = "attachment"
	}

	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Content-Disposition", fmt.Sprintf("%s; filename*=UTF-8''%s", disposition, url.PathEscape(filename)))
	w.Header().Set("Cache-Control", "public, max-age=86400")
	w.Write(rawBytes)
}

func extractRawBytes(data []byte) []byte {
	var m map[string]any
	if err := json.Unmarshal(data, &m); err == nil {
		if fileStr, ok := m["file"].(string); ok && fileStr != "" {
			if decoded, err := base64.StdEncoding.DecodeString(fileStr); err == nil {
				return decoded
			}
			if decoded, err := base64.RawStdEncoding.DecodeString(fileStr); err == nil {
				return decoded
			}
		}
	}
	return data
}
