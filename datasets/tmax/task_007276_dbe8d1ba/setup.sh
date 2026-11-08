#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx golang curl
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/app
    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/nginx/tmp/client_body
    mkdir -p /home/user/nginx/tmp/proxy
    mkdir -p /home/user/nginx/tmp/fastcgi
    mkdir -p /home/user/nginx/tmp/uwsgi
    mkdir -p /home/user/nginx/tmp/scgi

    # Create the Go API source file
    cat << 'EOF' > /home/user/app/api.go
package main

import (
	"fmt"
	"net"
	"net/http"
	"os"
)

func statsHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprint(w, `{"vms_running": 3, "qemu_cpu_usage": "45%", "qemu_mem_usage": "2GB"}`)
}

func main() {
	sockAddr := "/tmp/qemu_stats.sock"
	os.Remove(sockAddr)
	l, err := net.Listen("unix", sockAddr)
	if err != nil {
		panic(err)
	}
	defer l.Close()

	http.HandleFunc("/stats", statsHandler)
	http.Serve(l, nil)
}
EOF

    # Create the flawed Nginx configuration
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/logs/error.log;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/nginx/tmp/client_body;
    proxy_temp_path /home/user/nginx/tmp/proxy;
    fastcgi_temp_path /home/user/nginx/tmp/fastcgi;
    uwsgi_temp_path /home/user/nginx/tmp/uwsgi;
    scgi_temp_path /home/user/nginx/tmp/scgi;

    access_log /home/user/nginx/logs/access.log;

    server {
        listen 8080;
        server_name localhost;

        location /stats {
            # TYPO HERE: hyphen instead of underscore
            proxy_pass http://unix:/tmp/qemu-stats.sock;
        }
    }
}
EOF

    # Set permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
