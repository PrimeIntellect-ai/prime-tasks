#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/backend_v1.py
from http.server import BaseHTTPRequestHandler, HTTPServer

class V1Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'V1 Legacy API')

if __name__ == '__main__':
    server = HTTPServer(('localhost', 8001), V1Handler)
    server.serve_forever()
EOF
    chmod +x /home/user/backend_v1.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
