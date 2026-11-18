#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick wget git
    pip3 install pytest

    # Install Go 1.21
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    rm go1.21.6.linux-amd64.tar.gz
    ln -s /usr/local/go/bin/go /usr/bin/go

    # Create the image
    mkdir -p /app
    convert -size 1000x200 xc:white -pointsize 24 -fill black -draw "text 10,50 'Production Config Alert - CacheService offline. Last known bind: PORT=9090, AUTH_TOKEN=Z77-K9-BETA'" /app/dashboard_error.png

    # Create Git repository
    mkdir -p /home/user/cache-service
    cd /home/user/cache-service
    git config --global user.email "test@example.com"
    git config --global user.name "Test User"
    git init
    cat << 'EOF' > main.go
package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	port := os.Getenv("PORT")
	token := os.Getenv("AUTH_TOKEN")
	if port == "" { port = "8080" }

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if auth != "Bearer "+token {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		// GOOD STATE
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status": "ok"}`))
	})

	http.ListenAndServe(":"+port, nil)
}
EOF
    git add main.go
    git commit -m "Initial commit - stable health endpoint"

    # Introduce the regression
    sed -i 's/\/\/ GOOD STATE/panic("database connection lost")/' main.go
    git commit -am "Refactor connection handling"

    # Add some dummy commits on top to require actual debugging/bisection
    echo "// minor tweak" >> main.go
    git commit -am "Minor formatting"
    echo "// another tweak" >> main.go
    git commit -am "Update comments"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
