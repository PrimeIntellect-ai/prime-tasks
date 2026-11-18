#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx supervisor
    pip3 install pytest

    mkdir -p /home/user/nginx/logs /home/user/app /home/user/alerts
    mkdir -p /home/user/nginx/client_body /home/user/nginx/proxy_temp /home/user/nginx/fastcgi_temp /home/user/nginx/uwsgi_temp /home/user/nginx/scgi_temp

    cat << 'EOF' > /home/user/app/app.py
import socket
import os
import time

SOCK_FILE = '/home/user/app/app.sock'
if os.path.exists(SOCK_FILE):
    os.remove(SOCK_FILE)

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(SOCK_FILE)
server.listen(1)

while True:
    conn, addr = server.accept()
    request = conn.recv(1024)
    response = b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nHello World!"
    conn.sendall(response)
    conn.close()
EOF

    cat << 'EOF' > /home/user/nginx/nginx.conf
events {}
http {
    error_log /home/user/nginx/logs/error.log;
    access_log /home/user/nginx/logs/access.log;
    client_body_temp_path /home/user/nginx/client_body;
    proxy_temp_path /home/user/nginx/proxy_temp;
    fastcgi_temp_path /home/user/nginx/fastcgi_temp;
    uwsgi_temp_path /home/user/nginx/uwsgi_temp;
    scgi_temp_path /home/user/nginx/scgi_temp;

    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://unix:/home/user/app/app_wrong.sock;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
