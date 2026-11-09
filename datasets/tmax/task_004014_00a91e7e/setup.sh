#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest

    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/run
    mkdir -p /home/user/nginx/client_body /home/user/nginx/proxy_temp /home/user/nginx/fastcgi_temp /home/user/nginx/uwsgi_temp /home/user/nginx/scgi_temp

    cat << 'EOF' > /home/user/backend.py
#!/usr/bin/env python3
import socket, os, sys

sock_path = "/home/user/run/app.sock"
if os.path.exists(sock_path):
    os.remove(sock_path)

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(sock_path)
    s.listen(5)
    while True:
        conn, addr = s.accept()
        req = conn.recv(1024)
        if not req:
            conn.close()
            continue
        conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\nBackend Alive")
        conn.close()
except KeyboardInterrupt:
    sys.exit(0)
finally:
    if os.path.exists(sock_path):
        os.remove(sock_path)
EOF
    chmod +x /home/user/backend.py

    cat << 'EOF' > /home/user/nginx/nginx.conf
error_log /home/user/nginx/logs/error.log;
pid /home/user/nginx/nginx.pid;
worker_processes 1;
daemon off;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/nginx/logs/access.log;
    client_body_temp_path /home/user/nginx/client_body;
    proxy_temp_path /home/user/nginx/proxy_temp;
    fastcgi_temp_path /home/user/nginx/fastcgi_temp;
    uwsgi_temp_path /home/user/nginx/uwsgi_temp;
    scgi_temp_path /home/user/nginx/scgi_temp;

    server {
        listen 8080;
        location / {
            proxy_pass http://unix:/home/user/run/backend.sock;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
