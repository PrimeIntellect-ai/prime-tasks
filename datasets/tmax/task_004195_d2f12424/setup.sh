#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest requests

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nginx/client_body \
             /home/user/nginx/proxy \
             /home/user/nginx/fastcgi \
             /home/user/nginx/uwsgi \
             /home/user/nginx/scgi
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/nginx/error.log;
pid /home/user/nginx/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /home/user/nginx/access.log;
    client_body_temp_path /home/user/nginx/client_body;
    proxy_temp_path /home/user/nginx/proxy;
    fastcgi_temp_path /home/user/nginx/fastcgi;
    uwsgi_temp_path /home/user/nginx/uwsgi;
    scgi_temp_path /home/user/nginx/scgi;

    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:9001;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/backend.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import os
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if os.environ.get('ENV_MODE') != 'production':
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"Internal Server Error: Missing ENV_MODE")
            return

        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"status": "healthy", "service": "backend"}).encode('utf-8'))

if __name__ == '__main__':
    HTTPServer(('127.0.0.1', 9000), Handler).serve_forever()
EOF

    chmod -R 777 /home/user
