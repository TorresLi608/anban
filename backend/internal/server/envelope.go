package server

import (
	"encoding/base64"
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

func validFileEnvelope(e *envelope) bool {
	clone := *e
	clone.Ciphertext = "AA=="
	if !validEnvelope(&clone) {
		return false
	}
	b, err := base64.StdEncoding.DecodeString(e.Ciphertext)
	return err == nil && len(b) > 0 && len(b) <= 28<<20
}
