#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip make
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/db_service.py
import socket
import time
import os

with open('/home/user/data.db', 'w') as f:
    f.write('dummy data')

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 8080))
s.listen(5)

while True:
    try:
        conn, addr = s.accept()
        conn.close()
    except:
        pass
EOF

mkdir -p /app/metrics-aggregator-1.2.0

cat << 'EOF' > /app/metrics-aggregator-1.2.0/config.py
DB_PORT = 8081
EOF

cat << 'EOF' > /app/metrics-aggregator-1.2.0/server.py
import socket
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
import config

try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(('127.0.0.1', config.DB_PORT))
    s.close()
except Exception as e:
    print(f"Failed to connect to database: {e}")
    sys.exit(1)

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status": "ok"}')
        elif self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'metrics_data')
        else:
            self.send_response(404)
            self.end_headers()

server = HTTPServer(('127.0.0.1', 9090), MetricsHandler)
server.serve_forever()
EOF

cat << 'EOF' > /app/metrics-aggregator-1.2.0/Makefile
run:
    python3 server.py
EOF

chmod -R 777 /home/user
chmod -R 777 /app
