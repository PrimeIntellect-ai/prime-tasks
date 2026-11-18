#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang nginx
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/data/subdir

    # Create dummy files
    dd if=/dev/zero of=/home/user/app/data/file1.bin bs=1000 count=1
    dd if=/dev/zero of=/home/user/app/data/subdir/file2.bin bs=2000 count=1
    dd if=/dev/zero of=/home/user/app/data/subdir/file3.bin bs=1500 count=1

    # Nginx config
    cat << 'EOF' > /home/user/app/nginx.conf
worker_processes 1;
pid /home/user/app/nginx.pid;
error_log /home/user/app/error.log;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/app/access.log;
    client_body_temp_path /home/user/app/client_body;
    proxy_temp_path /home/user/app/proxy_temp;
    fastcgi_temp_path /home/user/app/fastcgi_temp;
    uwsgi_temp_path /home/user/app/uwsgi_temp;
    scgi_temp_path /home/user/app/scgi_temp;

    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://unix:/home/user/app/wrong_backend.sock;
        }
    }
}
EOF

    # Go backend
    cat << 'EOF' > /home/user/app/main.go
package main

import (
	"fmt"
	"net/http"
)

func statusHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "{}")
}

func main() {
	http.HandleFunc("/status", statusHandler)
	http.ListenAndServe(":9000", nil)
}
EOF

    # Start Nginx automatically on bash login to satisfy the running process requirement
    echo 'ps aux | grep -v grep | grep -q nginx || nginx -c /home/user/app/nginx.conf' >> /etc/bash.bashrc

    chmod -R 777 /home/user
