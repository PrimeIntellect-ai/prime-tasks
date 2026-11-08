#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx
    pip3 install pytest numpy

    mkdir -p /app/vendor/simple_service
    cat << 'EOF' > /app/vendor/simple_service/server.py
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(f"Served by {sys.argv[2]}".encode())

if __name__ == '__main__':
    port = int(sys.argv[2])
    server = HTTPServer(('127.0.0.1', port), Handler)
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/nginx
    chmod -R 777 /home/user
    chmod -R 777 /app
