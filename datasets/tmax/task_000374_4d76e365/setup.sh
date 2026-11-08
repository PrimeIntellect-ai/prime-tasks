#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd curl
    pip3 install pytest requests

    mkdir -p /app

    cat << 'EOF' > /app/kv_store.py
import socket
import time

time.sleep(3)
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 8001))
s.listen(5)

while True:
    conn, addr = s.accept()
    data = conn.recv(1024)
    if b'PING' in data:
        conn.sendall(b'PONG\n')
    conn.close()
EOF

    cat << 'EOF' > /app/backend.py
import socket
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

# Check KV store
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(('127.0.0.1', 8001))
    s.close()
except ConnectionRefusedError:
    sys.exit(1)

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"data": "success"}).encode())

server = HTTPServer(('127.0.0.1', 8002), RequestHandler)
server.serve_forever()
EOF

    cat << 'EOF' > /app/frontend.py
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            req = urllib.request.urlopen('http://127.0.0.1:8002' + self.path)
            data = req.read()
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(data)
        except Exception:
            self.send_response(502)
            self.end_headers()

server = HTTPServer(('127.0.0.1', 8003), RequestHandler)
server.serve_forever()
EOF

    cat << 'EOF' > /app/start_all.sh
#!/bin/bash
python3 /app/kv_store.py &
python3 /app/backend.py &
python3 /app/frontend.py &
EOF

    chmod +x /app/start_all.sh
    chmod -R 755 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
