#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/nginx/client_body
    mkdir -p /home/user/nginx/proxy_temp
    mkdir -p /home/user/nginx/fastcgi_temp
    mkdir -p /home/user/nginx/uwsgi_temp
    mkdir -p /home/user/nginx/scgi_temp
    mkdir -p /home/user/backup

    cat << 'EOF' > /home/user/app/server.py
import socket
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

SOCKET_FILE = "/home/user/app/app.sock"

class UnixSocketHttpServer(HTTPServer):
    def get_request(self):
        request, client_address = self.socket.accept()
        return (request, ["local"])

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Hello World\n")

if os.path.exists(SOCKET_FILE):
    os.remove(SOCKET_FILE)

server = UnixSocketHttpServer(SOCKET_FILE, RequestHandler)
server.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.socket.bind(SOCKET_FILE)
server.socket.listen(1)
server.serve_forever()
EOF

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
    proxy_temp_path /home/user/nginx/proxy_temp;
    fastcgi_temp_path /home/user/nginx/fastcgi_temp;
    uwsgi_temp_path /home/user/nginx/uwsgi_temp;
    scgi_temp_path /home/user/nginx/scgi_temp;

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://unix:/home/user/app/wrong.sock;
        }
    }
}
EOF

    chmod -R 777 /home/user
