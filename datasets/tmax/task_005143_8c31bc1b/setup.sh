#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/nginx
    mkdir -p /home/user/nginx/logs

    cat << 'EOF' > /home/user/app/server.py
import socket
import os
import sys

SOCKET_FILE = "app.sock"
LOG_FILE = "app.log"

if os.path.exists(SOCKET_FILE):
    os.remove(SOCKET_FILE)

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(SOCKET_FILE)
server.listen(1)

with open(LOG_FILE, "a") as f:
    f.write("Server started\n")

while True:
    conn, addr = server.accept()
    data = conn.recv(1024)
    if not data:
        break

    response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nHello from Python app!"
    conn.sendall(response.encode('utf-8'))
    conn.close()
EOF

    cat << 'EOF' > /home/user/app/start_app.sh
#!/bin/bash
# Broken: runs in current directory instead of /home/user/app
nohup python3 server.py > /dev/null 2>&1 &
EOF
    chmod +x /home/user/app/start_app.sh

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
daemon on;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/logs/error.log;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/nginx/logs/access.log;
    server {
        listen 8080;
        server_name localhost;

        location / {
            # BROKEN PATH
            proxy_pass http://unix:/home/user/wrong_path/app.sock;
        }
    }
}
EOF

    chown -R user:user /home/user/app
    chown -R user:user /home/user/nginx

    chmod -R 777 /home/user
