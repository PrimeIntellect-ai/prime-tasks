#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl socat psmisc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/appstack/run
    mkdir -p /home/user/backups

    cat << 'EOF' > /home/user/appstack/config.json
{
  "upstream_socket": "/tmp/wrong_app.sock",
  "proxy_port": 8080
}
EOF

    cat << 'EOF' > /home/user/appstack/manager.sh
#!/bin/bash
echo "This script is broken"
exit 1
EOF
    chmod +x /home/user/appstack/manager.sh

    cat << 'EOF' > /home/user/appstack/backend.py
#!/usr/bin/env python3
import socket
import os
import sys

sock_path = os.environ.get("APP_SOCKET_PATH", "/tmp/wrong_app.sock")

if os.path.exists(sock_path):
    os.remove(sock_path)

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sock_path)
server.listen(1)

while True:
    try:
        conn, addr = server.accept()
        data = conn.recv(1024)
        if b"GET /status" in data:
            response = b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\": \"healthy\", \"component\": \"backend\"}"
        else:
            response = b"HTTP/1.1 404 Not Found\r\n\r\n"
        conn.sendall(response)
        conn.close()
    except Exception:
        break
EOF
    chmod +x /home/user/appstack/backend.py

    cat << 'EOF' > /home/user/appstack/proxy.py
#!/usr/bin/env python3
import socket
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

with open('/home/user/appstack/config.json', 'r') as f:
    config = json.load(f)

upstream = config.get("upstream_socket")

class ProxyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if not os.path.exists(upstream):
            self.send_response(502)
            self.end_headers()
            self.wfile.write(b"502 Bad Gateway: Upstream socket not found")
            return

        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            client.connect(upstream)
            request = f"GET {self.path} HTTP/1.1\r\nHost: localhost\r\n\r\n".encode('utf-8')
            client.sendall(request)
            response = client.recv(4096)

            # Simple parsing for our dummy setup
            parts = response.split(b"\r\n\r\n", 1)
            body = parts[1] if len(parts) > 1 else b""

            self.send_response(200)
            self.end_headers()
            self.wfile.write(body)
        except Exception as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(b"502 Bad Gateway: Connection failed")
        finally:
            client.close()

server = HTTPServer(('127.0.0.1', 8080), ProxyHandler)
server.serve_forever()
EOF
    chmod +x /home/user/appstack/proxy.py

    chown -R user:user /home/user/appstack /home/user/backups
    chmod -R 777 /home/user
