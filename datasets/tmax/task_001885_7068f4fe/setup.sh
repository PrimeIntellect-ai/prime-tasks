#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx expect curl
pip3 install pytest requests

mkdir -p /home/user/nginx/logs
mkdir -p /home/user/nginx/temp
mkdir -p /home/user/backend

cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/logs/error.log;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/nginx/logs/access.log;
    client_body_temp_path /home/user/nginx/temp/client_body;
    proxy_temp_path /home/user/nginx/temp/proxy;
    fastcgi_temp_path /home/user/nginx/temp/fastcgi;
    uwsgi_temp_path /home/user/nginx/temp/uwsgi;
    scgi_temp_path /home/user/nginx/temp/scgi;

    server {
        listen 8080;
        server_name localhost;

        location / {
            # Intentionally broken port
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

cat << 'EOF' > /home/user/backend/app.py
import os
import sys
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

if os.environ.get("TZ") != "Europe/Paris":
    print("Fatal: TZ environment variable must be Europe/Paris")
    sys.exit(1)

print("Enter startup pin code:")
pin = input().strip()
if pin != "8374":
    print("Invalid pin!")
    sys.exit(1)

class SimpleHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        response = json.dumps({"status": "ok", "timezone": os.environ.get("TZ")})
        self.wfile.write(response.encode('utf-8'))

    def log_message(self, format, *args):
        pass

print("Starting server on port 9001...")
server = HTTPServer(('127.0.0.1', 9001), SimpleHandler)
server.serve_forever()
EOF

chmod +x /home/user/backend/app.py

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/nginx /home/user/backend
chmod -R 777 /home/user
