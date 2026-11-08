#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip supervisor curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/app.py
import os
import sys
import socket

if os.environ.get("TZ") != "Europe/Berlin":
    print("Error: Missing or incorrect TZ environment variable.")
    sys.exit(1)

if len(sys.argv) < 2:
    print("Usage: python3 app.py <socket_path>")
    sys.exit(1)

sock_path = sys.argv[1]

# Bug: Missing os.unlink(sock_path) if os.path.exists(sock_path)

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sock_path)
server.listen(1)

print(f"Listening on {sock_path}")

while True:
    try:
        conn, addr = server.accept()
        data = conn.recv(1024)
        if data:
            response = b"HTTP/1.1 200 OK\r\nContent-Length: 23\r\n\r\nHello from Microservice"
            conn.sendall(response)
        conn.close()
    except Exception:
        pass
EOF

    cat << 'EOF' > /home/user/supervisord.conf
[supervisord]
logfile=/home/user/supervisord.log
pidfile=/home/user/supervisord.pid
nodaemon=false

[program:myapp]
command=python3 /home/user/app.py /tmp/wrong.sock
autorestart=false
redirect_stderr=true
EOF

    chmod -R 777 /home/user
