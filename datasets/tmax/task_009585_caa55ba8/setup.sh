#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go curl
    pip3 install pytest

    mkdir -p /home/user/legacy-svc
    cd /home/user/legacy-svc
    go mod init legacy-svc

    cat << 'EOF' > /home/user/legacy-svc/main.go
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

const secret = "super-secret-123"

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f, err := os.OpenFile("/home/user/legacy-svc/app.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err == nil {
			logMsg := fmt.Sprintf("Request: %s, DebugToken: %s\n", r.URL.Path, r.Header.Get("X-Debug-Token"))
			f.WriteString(logMsg)
			f.Close()
		}

		// Leak debug token in response
		if token := r.Header.Get("X-Debug-Token"); token != "" {
			w.Header().Set("X-Debug-Token", token)
		}

		next.ServeHTTP(w, r)
	})
}

func authHandler(w http.ResponseWriter, r *http.Request) {
	authHeader := r.Header.Get("Authorization")
	if authHeader == secret {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
		return
	}
	w.WriteHeader(http.StatusUnauthorized)
	w.Write([]byte("Unauthorized"))
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/auth", authHandler)

	server := &http.Server{
		Addr:    "127.0.0.1:8080",
		Handler: loggingMiddleware(mux),
	}
	server.ListenAndServe()
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
