package server

import (
	"encoding/base64"
	"encoding/json"
	"testing"
)

func TestDetectContentType(t *testing.T) {
	cases := []struct {
		filename string
		data     []byte
		expected string
	}{
		{"test.pdf", nil, "application/pdf"},
		{"report.PDF", nil, "application/pdf"},
		{"photo.jpg", nil, "image/jpeg"},
		{"image.png", nil, "image/png"},
		{"clip.mp4", nil, "video/mp4"},
		{"voice.m4a", nil, "audio/mp4"},
		{"doc.txt", nil, "text/plain; charset=utf-8"},
		{"unknown.xyz", []byte("%PDF-1.4..."), "application/pdf"},
	}

	for _, c := range cases {
		got := detectContentType(c.filename, c.data)
		if got != c.expected {
			t.Errorf("detectContentType(%q) = %q; want %q", c.filename, got, c.expected)
		}
	}
}

func TestSanitizeFilename(t *testing.T) {
	cases := []struct {
		input    string
		expected string
	}{
		{"normal.pdf", "normal.pdf"},
		{"../../etc/passwd.pdf", "passwd.pdf"},
		{"path/to/my file.png", "my file.png"},
		{"", "file.bin"},
		{"   ", "file.bin"},
	}

	for _, c := range cases {
		got := sanitizeFilename(c.input)
		if got != c.expected {
			t.Errorf("sanitizeFilename(%q) = %q; want %q", c.input, got, c.expected)
		}
	}
}

func TestExtractRawBytes(t *testing.T) {
	orig := []byte("hello world pdf binary bytes")
	payload := map[string]string{
		"file": base64.StdEncoding.EncodeToString(orig),
	}
	rawJSON, _ := json.Marshal(payload)

	extracted := extractRawBytes(rawJSON)
	if string(extracted) != string(orig) {
		t.Fatalf("extractRawBytes failed; got %q; want %q", string(extracted), string(orig))
	}

	plain := []byte("already plain data")
	if string(extractRawBytes(plain)) != string(plain) {
		t.Fatalf("extractRawBytes altered plain data")
	}
}
