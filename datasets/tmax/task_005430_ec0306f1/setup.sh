#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl golang-go
    pip3 install pytest packaging flask requests

    mkdir -p /home/user/app/nginx/logs
    mkdir -p /home/user/app/nginx/temp

    cat << 'EOF' > /home/user/app/builder.go
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
)

func main() {
	http.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status": "ok"}`))
	})
	http.HandleFunc("/trigger", func(w http.ResponseWriter, r *http.Request) {
		var req map[string]string
		json.NewDecoder(r.Body).Decode(&req)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(fmt.Sprintf(`{"triggered": "%s"}`, req["target"])))
	})
	http.ListenAndServe("127.0.0.1:8001", nil)
}
EOF

    cd /home/user/app
    go build -o builder builder.go
    rm builder.go
    chmod +x builder

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
