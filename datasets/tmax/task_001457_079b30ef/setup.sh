#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx openssl curl
pip3 install pytest requests

mkdir -p /home/user/app/releases/v1
cat << 'EOF' > /home/user/app/releases/v1/app.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class SimpleHTTPRequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{"status": "ok"}')

httpd = HTTPServer(('127.0.0.1', 8080), SimpleHTTPRequestHandler)
httpd.serve_forever()
EOF
chmod +x /home/user/app/releases/v1/app.py

ln -s /home/user/app/releases/v2 /home/user/app/current

cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
error_log /home/user/nginx_error.log;
pid /home/user/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/nginx_access.log;
    client_body_temp_path /home/user/client_body;
    fastcgi_temp_path /home/user/fastcgi_temp;
    proxy_temp_path /home/user/proxy_temp;
    scgi_temp_path /home/user/scgi_temp;
    uwsgi_temp_path /home/user/uwsgi_temp;

    server {
        listen 8443 ssl;
        server_name localhost;

        # ssl_certificate /path/to/cert.pem;
        # ssl_certificate_key /path/to/key.pem;

        location / {
            proxy_pass http://localhost:8080;
        }
    }
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
