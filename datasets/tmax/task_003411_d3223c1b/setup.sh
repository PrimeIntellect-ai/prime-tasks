#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang nginx curl logrotate
pip3 install pytest

mkdir -p /home/user/app /home/user/logs /home/user/repos/project.git /home/user/public_html /home/user/nginx_temp

# Broken Nginx Config
cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/logs/nginx_error.log;
pid /home/user/nginx_temp/nginx.pid;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/nginx_temp/client_body;
    fastcgi_temp_path /home/user/nginx_temp/fastcgi_temp;
    proxy_temp_path /home/user/nginx_temp/proxy_temp;
    scgi_temp_path /home/user/nginx_temp/scgi_temp;
    uwsgi_temp_path /home/user/nginx_temp/uwsgi_temp;

    access_log /home/user/logs/nginx_access.log;

    server {
        listen 8080;
        server_name localhost;

        location /api/ {
            # BROKEN PORT: Should be 9090
            proxy_pass http://127.0.0.1:9099;
        }

        location /health {
            # BROKEN PORT: Should be 9090
            proxy_pass http://127.0.0.1:9099;
        }

        location /repos/ {
            alias /home/user/public_html/repos/;
            autoindex on;
        }
    }
}
EOF

# Broken Go app
cat << 'EOF' > /home/user/app/main.go
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})

	http.HandleFunc("/api/hook", func(w http.ResponseWriter, r *http.Request) {
		f, err := os.OpenFile("/home/user/logs/webhook.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			http.Error(w, "Failed to open log", http.StatusInternalServerError)
			return
		}
		defer f.Close()

		if _, err := f.WriteString("WEBHOOK_RECEIVED\n"); err != nil {
			http.Error(w, "Failed to write log", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusOK)
		w.Write([]byte("Success"))
	})

	// BROKEN PORT: Should be 9090
	fmt.Println("Starting server on :9091")
	log.Fatal(http.ListenAndServe(":9091", nil))
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
