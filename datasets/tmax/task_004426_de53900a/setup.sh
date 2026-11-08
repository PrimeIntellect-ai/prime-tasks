#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat netcat-openbsd golang
    pip3 install pytest requests

    mkdir -p /app
    cat << 'EOF' > /app/auth_service.go
package main
import (
    "fmt"
    "net/http"
)
func main() {
    http.HandleFunc("/login", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Set-Cookie", "session=12345ABC")
        fmt.Fprintf(w, "Login page")
    })
    http.HandleFunc("/redirect", func(w http.ResponseWriter, r *http.Request) {
        url := r.URL.Query().Get("url")
        if url != "" {
            http.Redirect(w, r, url, http.StatusFound)
        } else {
            http.Redirect(w, r, "/dashboard", http.StatusFound)
        }
    })
    http.ListenAndServe("127.0.0.1:8080", nil)
}
EOF

    cd /app
    go build -ldflags="-s -w" -o auth_service auth_service.go
    rm auth_service.go
    chmod +x auth_service

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
