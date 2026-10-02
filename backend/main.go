// Anban stores client-encrypted snapshots and attachments; backup passwords stay on device.
package main

import (
	"encoding/base64"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
)

const maxBody = 12 << 20

type envelope struct {
	Version    int    `json:"version"`
	Algorithm  string `json:"algorithm"`
	Iterations int    `json:"iterations"`
	Salt       string `json:"salt"`
	Nonce      string `json:"nonce"`
	Ciphertext string `json:"ciphertext"`
	MAC        string `json:"mac"`
}
type snapshot struct {
	Revision  uint64    `json:"revision"`
	UpdatedAt string    `json:"updatedAt"`
	Data      *envelope `json:"data"`
}

func validEnvelope(e *envelope) bool {
	if e.Version != 1 || e.Algorithm != "AES-256-GCM" || e.Iterations != 210000 {
		return false
	}
	for _, field := range []struct {
		value string
		size  int
	}{{e.Salt, 16}, {e.Nonce, 12}, {e.MAC, 16}} {
		b, err := base64.StdEncoding.DecodeString(field.value)
		if err != nil || len(b) != field.size {
			return false
		}
	}
	b, err := base64.StdEncoding.DecodeString(e.Ciphertext)
	return err == nil && len(b) > 0 && len(b) <= 8<<20
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func fail(w http.ResponseWriter, code int, message string) {
	writeJSON(w, code, map[string]string{"error": message})
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	s, err := newCloud()
	if err != nil {
		log.Fatal(err)
	}
	h := &http.Server{Addr: env("ANBAN_ADDR", "127.0.0.1:8080"), Handler: s, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 120 * time.Second, WriteTimeout: 120 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16 << 10}
	log.Printf("Anban encrypted vault listening on %s", h.Addr)
	log.Fatal(h.ListenAndServe())
}
