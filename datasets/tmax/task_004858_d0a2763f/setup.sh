#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_stack/nginx/logs
    mkdir -p /home/user/app_stack/nginx/temp
    mkdir -p /home/user/app_stack/backend

    cat << 'EOF' > /home/user/app_stack/backend/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer

class SimpleHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b"Backend operational!")

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 9091), SimpleHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/app_stack/nginx/nginx.conf
worker_processes 1;
error_log /home/user/app_stack/nginx/logs/error.log;
pid /home/user/app_stack/nginx/nginx.pid;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/app_stack/nginx/temp/client_body;
    fastcgi_temp_path /home/user/app_stack/nginx/temp/fastcgi;
    proxy_temp_path /home/user/app_stack/nginx/temp/proxy;
    scgi_temp_path /home/user/app_stack/nginx/temp/scgi;
    uwsgi_temp_path /home/user/app_stack/nginx/temp/uwsgi;

    access_log /home/user/app_stack/nginx/logs/access.log;

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://127.0.0.1:9095; # Intentional error: port should be 9091
        }
    }
}
EOF

    chmod +x /home/user/app_stack/backend/server.py
    chown -R user:user /home/user/app_stack
    chmod -R 777 /home/user
