#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/daemon.go
package main

import (
	"fmt"
	"net/http"
	"strconv"
	"time"
)

func handler(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("X-Admin-Bypass") != "true" || r.Header.Get("X-CSP-Enforce") != "none" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	if r.URL.Path == "/verify" {
		idStr := r.URL.Query().Get("id")
		id, err := strconv.Atoi(idStr)
		if err == nil {
			time.Sleep(2 * time.Millisecond)
			if id == 14992 {
				fmt.Fprint(w, "FLAG{g0_c0ncurr3ncy_byp4ss_x92}")
				return
			}
		}
		http.Error(w, "Not Found", http.StatusNotFound)
		return
	}
	http.Error(w, "Not Found", http.StatusNotFound)
}

func main() {
	http.HandleFunc("/", handler)
	http.ListenAndServe("127.0.0.1:8080", nil)
}
EOF

    cd /tmp
    go build -ldflags="-s -w" -o /app/auth_daemon daemon.go
    strip /app/auth_daemon
    rm daemon.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
