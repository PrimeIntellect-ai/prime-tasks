#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/run_fake

    # Create .profile with a typo
    cat << 'EOF' > /home/user/.profile
export APP_SOC=/home/user/run/app.sock
EOF

    # Create proxy.py
    cat << 'EOF' > /home/user/app/proxy.py
import socket
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

SOCKET_PATH = "/home/user/run/app.sock"

class ProxyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            client.connect(SOCKET_PATH)
            client.sendall(b"GET / HTTP/1.0\r\n\r\n")
            response = client.recv(1024).decode('utf-8')
            client.close()

            body = response.split("\r\n\r\n", 1)[1] if "\r\n\r\n" in response else response
            self.send_response(200)
            self.end_headers()
            self.wfile.write(body.encode('utf-8'))
        except Exception as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(b"502 Bad Gateway")

if __name__ == "__main__":
    server = HTTPServer(('127.0.0.1', 8080), ProxyHandler)
    server.serve_forever()
EOF

    # Create flawed backend.py
    cat << 'EOF' > /home/user/app/backend.py
import socket
import os
import sys

sock_path = os.environ.get("APP_SOCK")
if not sock_path:
    print("Error: APP_SOCK not set")
    sys.exit(1)

# Missing directory creation logic here...
if os.path.exists(sock_path):
    os.remove(sock_path)

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sock_path)
server.listen(1)

while True:
    conn, _ = server.accept()
    data = conn.recv(1024)
    if data:
        conn.sendall(b"HTTP/1.0 200 OK\r\n\r\nBackend Operational")
    conn.close()
EOF

    chown -R user:user /home/user/app /home/user/.profile
    chmod +x /home/user/app/*.py

    chmod -R 777 /home/user
