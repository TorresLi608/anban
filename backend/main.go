// Anban stores client-encrypted snapshots and attachments; backup passwords stay on device.
package main

import (
	"log"
	"net/http"
	"time"

	"anban/backend/internal/config"
	"anban/backend/internal/server"
)

func run() error {
	cfg := config.Load()
	s, err := server.New(cfg)
	if err != nil {
		return err
	}
	defer s.Close()
	h := &http.Server{Addr: cfg.Addr, Handler: s, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 120 * time.Second, WriteTimeout: 120 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16 << 10}
	log.Printf("Anban encrypted vault listening on %s", h.Addr)
	return h.ListenAndServe()
}

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}
