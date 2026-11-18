#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl logrotate
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/staging/logs
    mkdir -p /home/user/staging/client_body_temp
    mkdir -p /home/user/staging/proxy_temp
    mkdir -p /home/user/staging/fastcgi_temp
    mkdir -p /home/user/staging/uwsgi_temp
    mkdir -p /home/user/staging/scgi_temp

    # Create the backend app
    cat << 'EOF' > /home/user/staging/app.py
import socket
import os

sock_path = '/tmp/staging_app.sock'
if os.path.exists(sock_path):
    os.remove(sock_path)

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sock_path)
server.listen(1)

print("Backend listening on", sock_path)

while True:
    conn, addr = server.accept()
    request = conn.recv(1024)
    if not request:
        break
    response = b"HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 15\r\n\r\nCapacity: 85%\r\n"
    conn.sendall(response)
    conn.close()
EOF
    chmod +x /home/user/staging/app.py

    # Create the broken nginx config
    cat << 'EOF' > /home/user/staging/nginx.conf
worker_processes 1;
error_log /home/user/staging/logs/error.log;
pid /home/user/staging/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/staging/logs/access.log;

    server {
        listen 8080;

        location / {
            proxy_pass http://unix:/tmp/wrong_path.sock;
        }
    }
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
