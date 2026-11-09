#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest

    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/app
    mkdir -p /home/user/storage
    mkdir -p /home/user/deploy

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
error_log /home/user/nginx/logs/error.log;
pid /home/user/nginx/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/nginx/logs/access.log;

    server {
        listen 127.0.0.1:8080;

        location / {
            # Intentional port mismatch to test diagnostic skills (9001 instead of 9000)
            proxy_pass http://127.0.0.1:9001;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/storage/data.json
{"status": "online", "version": "1.0.3"}
EOF

    cat << 'EOF' > /home/user/app/server.py
import http.server
import socketserver
import json
import os

PORT = 8000 # Bug: Wrong port, should be 9000
DATA_PATH = "mnt/data.json"

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/status':
            try:
                with open(DATA_PATH, 'r') as f:
                    data = f.read()
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(data.encode())
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == "__main__":
    # Crash on startup if data doesn't exist
    if not os.path.exists(DATA_PATH):
        raise RuntimeError(f"Critical data missing at {DATA_PATH}. Check mount points.")

    with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
        httpd.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
