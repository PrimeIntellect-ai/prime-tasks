#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/app
    mkdir -p /tmp/uploads

    cat << 'EOF' > /home/user/app/server.go
package main

import (
	"io"
	"net/http"
	"os"
	"path/filepath"
)

const secretToken = "AUTH_TK_8849201aB_x9"

func uploadHandler(w http.ResponseWriter, r *http.Request) {
	authHeader := r.Header.Get("Authorization")
	if authHeader != "Bearer "+secretToken {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	dest := r.URL.Query().Get("dest")
	if dest == "" {
		http.Error(w, "Missing dest parameter", http.StatusBadRequest)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Error reading body", http.StatusInternalServerError)
		return
	}

	// Vulnerable path construction
	outPath := filepath.Join("/tmp/uploads", dest)

	err = os.WriteFile(outPath, body, 0644)
	if err != nil {
		http.Error(w, "Error writing file", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte("Upload successful"))
}

func main() {
	http.HandleFunc("/upload", uploadHandler)
	http.ListenAndServe("127.0.0.1:9090", nil)
}
EOF

    cd /home/user/app
    go build -o server server.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /tmp/uploads
