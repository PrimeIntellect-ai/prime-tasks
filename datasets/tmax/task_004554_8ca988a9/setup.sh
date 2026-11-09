#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx cron curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/deploy

    cat << 'EOF' > /home/user/deploy/nginx.conf
worker_processes 1;
error_log /home/user/deploy/error.log;
pid /home/user/deploy/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/deploy/access.log;
    client_body_temp_path /home/user/deploy/client_body;
    proxy_temp_path /home/user/deploy/proxy;
    fastcgi_temp_path /home/user/deploy/fastcgi;
    uwsgi_temp_path /home/user/deploy/uwsgi;
    scgi_temp_path /home/user/deploy/scgi;

    server {
        listen 127.0.0.1:8080;
        server_name localhost;

        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/deploy/app.py
import http.server
import socketserver
import json
import sys

try:
    with open('/home/user/deploy/config.json', 'r') as f:
        config = json.load(f)
except Exception as e:
    print(f"Failed to load config: {e}")
    sys.exit(1)

PORT = 5001

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"message": "Hello World"}')

with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    print(f"Serving at port {PORT}")
    httpd.serve_forever()
EOF

    chmod -R 777 /home/user
