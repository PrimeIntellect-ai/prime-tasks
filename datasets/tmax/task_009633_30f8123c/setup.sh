#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go nginx curl openssl
    pip3 install pytest

    mkdir -p /home/user/app
    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/certs

    cat << 'EOF' > /home/user/app/main.go
package main

import (
	"fmt"
	"net/http"
)

func handler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "Go Backend Online")
}

func main() {
	http.HandleFunc("/api", handler)
	// Broken: tries to bind to privileged port
	http.ListenAndServe("127.0.0.1:80", nil)
}
EOF

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/logs/error.log;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/nginx/logs/access.log;
    client_body_temp_path /home/user/nginx/client_body;
    fastcgi_temp_path /home/user/nginx/fastcgi_temp;
    proxy_temp_path /home/user/nginx/proxy_temp;
    scgi_temp_path /home/user/nginx/scgi_temp;
    uwsgi_temp_path /home/user/nginx/uwsgi_temp;

    server {
        listen 8080;
        server_name localhost;

        location /api {
            proxy_pass http://127.0.0.1:9090;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
