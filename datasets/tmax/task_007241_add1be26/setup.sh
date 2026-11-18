#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx expect netcat-openbsd curl openssl
    pip3 install pytest

    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/nginx/client_body_temp
    mkdir -p /home/user/nginx/proxy_temp
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer

class SimpleHTTPRequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/status':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not Found')

httpd = HTTPServer(('127.0.0.1', 9000), SimpleHTTPRequestHandler)
httpd.serve_forever()
EOF

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

    server {
        listen 8443 ssl;
        server_name localhost;

        ssl_certificate /home/user/nginx/certs/server.crt;
        ssl_certificate_key /home/user/nginx/certs/server.key;

        location / {
            proxy_pass http://127.0.0.1:9001;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/nginx /home/user/app
    chmod -R 777 /home/user
