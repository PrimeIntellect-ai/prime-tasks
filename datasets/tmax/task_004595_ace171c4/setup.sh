#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/nginx/client_body_temp
    mkdir -p /home/user/nginx/proxy_temp
    mkdir -p /home/user/nginx/fastcgi_temp
    mkdir -p /home/user/nginx/uwsgi_temp
    mkdir -p /home/user/nginx/scgi_temp
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/backend.py
import os
import socketserver
import http.server
import json
import sys

sock_path = os.environ.get('APP_SOCK')
if not sock_path:
    print("APP_SOCK environment variable not set")
    sys.exit(1)

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        response = {"status": "ok", "message": "Migration Complete"}
        self.wfile.write(json.dumps(response).encode())

# Ensure old socket is removed
if os.path.exists(sock_path):
    os.remove(sock_path)

with socketserver.UnixStreamServer(sock_path, Handler) as httpd:
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        if os.path.exists(sock_path):
            os.remove(sock_path)
EOF
    chmod +x /home/user/app/backend.py

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/logs/error.log;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/nginx/client_body_temp;
    proxy_temp_path /home/user/nginx/proxy_temp;
    fastcgi_temp_path /home/user/nginx/fastcgi_temp;
    uwsgi_temp_path /home/user/nginx/uwsgi_temp;
    scgi_temp_path /home/user/nginx/scgi_temp;

    access_log /home/user/nginx/logs/access.log;

    upstream backend {
        server unix:/tmp/legacy.sock;
    }

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

    chmod -R 777 /home/user
