#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
    cat /home/user/.ssh/id_rsa.pub >> /home/user/.ssh/authorized_keys

    # Configure sshd for unprivileged execution
    cat << 'EOF' > /home/user/sshd_config
Port 2222
HostKey /home/user/.ssh/id_rsa
AuthorizedKeysFile /home/user/.ssh/authorized_keys
StrictModes no
PidFile /home/user/sshd.pid
UsePAM yes
EOF

    # Mock API
    cat << 'EOF' > /home/user/mock_api.py
import http.server
import socketserver

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"SECRET_UPSTREAM_DATA")

with socketserver.TCPServer(("127.0.0.2", 8080), Handler) as httpd:
    httpd.serve_forever()
EOF

    # Broken backend
    mkdir -p /home/user/backend
    cat << 'EOF' > /home/user/backend/app.py
import socket
import os
import urllib.request
import json

SOCKET_FILE = "/var/run/backend.sock" # Broken path

if os.path.exists(SOCKET_FILE):
    os.remove(SOCKET_FILE)

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(SOCKET_FILE)
server.listen(1)

while True:
    conn, _ = server.accept()
    request = conn.recv(1024)
    if not request:
        break

    # Fetch from tunneled API
    api_url = os.environ.get("TUNNELED_API_URL", "http://127.0.0.1:9090")
    try:
        resp = urllib.request.urlopen(api_url).read()
    except Exception as e:
        resp = b"ERROR"

    http_response = b"HTTP/1.1 200 OK\r\n\r\n" + resp
    conn.sendall(http_response)
    conn.close()
EOF

    mkdir -p /run/sshd
    chmod -R 777 /home/user
