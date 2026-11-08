#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr openssl golang-go imagemagick
    pip3 install pytest

    mkdir -p /app/evidence
    mkdir -p /app/server/uploads

    # Generate the ransom note image
    convert -size 400x100 xc:white -pointsize 24 -fill black -annotate +10+50 'PREFIX: G0ph3rH4x_' /app/evidence/ransom_note.png

    # Generate the encrypted secret
    echo -n "AUTH_TOKEN: 8f9b2a1c-7e6d-4f5a-9b2c-1d9e8f7a6b5c" > /tmp/secret.txt
    openssl enc -aes-256-cbc -pbkdf2 -salt -pass pass:G0ph3rH4x_714 -in /tmp/secret.txt -out /app/evidence/secret.enc
    rm /tmp/secret.txt

    # Create the vulnerable Go server
    cat << 'EOF' > /app/server/main.go
package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
)

func uploadHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	err := r.ParseMultipartForm(10 << 20)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	file, handler, err := r.FormFile("file")
	if err != nil {
		http.Error(w, "Error Retrieving the File", http.StatusBadRequest)
		return
	}
	defer file.Close()

	// VULNERABLE: Path traversal via handler.Filename
	dstPath := filepath.Join("/app/server/uploads", handler.Filename)

	dst, err := os.Create(dstPath)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer dst.Close()

	if _, err := io.Copy(dst, file); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	fmt.Fprintf(w, "Successfully Uploaded File\n")
}

func main() {
	http.HandleFunc("/upload", uploadHandler)
	fmt.Println("Server listening on :8080")
	http.ListenAndServe(":8080", nil)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
