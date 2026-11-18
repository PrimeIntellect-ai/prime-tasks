#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        golang \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app

    # Create the sticky note image with the secret key
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -annotate +10+50 'SUP3R_S3CR3T_K3Y_9921' /app/sticky_note.png

    # Create the legacy_api backend in Go
    cat << 'EOF' > /app/legacy_api.go
package main

import (
	"fmt"
	"net/http"
)

func handler(w http.ResponseWriter, r *http.Request) {
	key := r.Header.Get("X-Admin-Key")
	if key == "SUP3R_S3CR3T_K3Y_9921" {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintln(w, "Success")
	} else {
		w.WriteHeader(http.StatusForbidden)
		fmt.Fprintln(w, "Forbidden")
	}
}

func main() {
	// This string will be visible in the binary via strings/objdump
	fmt.Println("Listening on :13337")
	http.HandleFunc("/data", handler)
	http.ListenAndServe("127.0.0.1:13337", nil)
}
EOF

    cd /app
    go build -o legacy_api legacy_api.go
    rm legacy_api.go
    chmod +x legacy_api

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
