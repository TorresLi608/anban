package server

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"strings"

	"github.com/minio/minio-go/v7"
)

const maxFile = 40 << 20 // 20 MB attachment plus base64 and encryption envelope.
func (c *Server) file(w http.ResponseWriter, r *http.Request, user string) {
	if r.URL.Path == "/api/v1/files" && r.Method == "POST" {
		var e envelope
		if !decode(w, r, &e, maxFile) {
			return
		}
		// File envelopes use the same format with a larger ciphertext allowance.
		if !validFileEnvelope(&e) {
			fail(w, 400, "invalid encrypted file")
			return
		}
		b, _ := json.Marshal(e)
		id := randomID()
		key := user + "/" + id
		if _, err := c.objects.PutObject(r.Context(), c.bucket, key, bytes.NewReader(b), int64(len(b)), minio.PutObjectOptions{ContentType: "application/octet-stream"}); err != nil {
			fail(w, 502, "附件上传失败")
			return
		}
		if _, err := c.db.ExecContext(r.Context(), `INSERT INTO anban_files(id,user_id) VALUES($1,$2)`, id, user); err != nil {
			_ = c.objects.RemoveObject(r.Context(), c.bucket, key, minio.RemoveObjectOptions{})
			fail(w, 500, "附件索引保存失败")
			return
		}
		writeJSON(w, 200, map[string]string{"id": id})
		return
	}
	id := strings.TrimPrefix(r.URL.Path, "/api/v1/files/")
	if !filePattern.MatchString(id) {
		fail(w, 404, "附件不存在")
		return
	}
	if r.Method != "GET" {
		fail(w, 405, "method not allowed")
		return
	}
	var exists bool
	if err := c.db.QueryRowContext(r.Context(), `SELECT EXISTS(SELECT 1 FROM anban_files WHERE id=$1 AND user_id=$2)`, id, user).Scan(&exists); err != nil {
		fail(w, 503, "附件索引不可用")
		return
	}
	if !exists {
		fail(w, 404, "附件不存在")
		return
	}
	object, err := c.objects.GetObject(r.Context(), c.bucket, user+"/"+id, minio.GetObjectOptions{})
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
	w.Header().Set("Content-Type", "application/json")
	w.Write(b)
}
