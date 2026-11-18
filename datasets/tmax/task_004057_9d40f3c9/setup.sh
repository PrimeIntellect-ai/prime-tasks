#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy.go
package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	if os.Getenv("TZ") != "UTC" || os.Getenv("LC_ALL") != "C" {
		os.Exit(1)
	}

	http.HandleFunc("/secret_token_v2", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		fmt.Fprint(w, "MIGRATION_AUTH_9921_ACCEPTED")
	})

	http.ListenAndServe("127.0.0.1:9090", nil)
}
EOF

    go build -ldflags="-s -w" -o /app/legacy_api /tmp/legacy.go
    rm /tmp/legacy.go
    chmod +x /app/legacy_api

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
