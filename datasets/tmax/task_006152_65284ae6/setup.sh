#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang curl openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/uploads
    mkdir -p /home/user/.ssh

    cat << 'EOF' > /home/user/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... legitimate@admin
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... hacker@evil
EOF

    cat << 'EOF' > /home/user/app/upload_server.go
package main

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"path/filepath"
)

func uploadHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	filename := r.URL.Query().Get("filename")
	if filename == "" {
		http.Error(w, "Filename required", http.StatusBadRequest)
		return
	}

	body, err := ioutil.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Error reading body", http.StatusInternalServerError)
		return
	}

	// VULNERABILITY: Path Traversal
	targetPath := filepath.Join("/home/user/app/uploads", filename)

	err = os.WriteFile(targetPath, body, 0644)
	if err != nil {
		http.Error(w, "Error writing file", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, "File uploaded successfully")
}

func main() {
	http.HandleFunc("/upload", uploadHandler)
	http.ListenAndServe(":8080", nil)
}
EOF

    chmod -R 777 /home/user
