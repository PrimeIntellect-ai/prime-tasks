#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/service/configs

    cat << 'EOF' > /home/user/service/configs/production.json
{"auth_mode": "strict", "debug": false}
EOF

    cat << 'EOF' > /home/user/service/configs/revoked.json
{"auth_mode": "none", "debug": true, "revoked": true}
EOF

    ln -s /home/user/service/configs/revoked.json /home/user/service/config.json

    cat << 'EOF' > /home/user/service/daemon.py
import os
import sys
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status": "healthy", "uptime": "stable"}')
        else:
            self.send_response(404)
            self.end_headers()

def main():
    if not os.path.exists('/home/user/service/config.json'):
        sys.exit(1)

    with open('/home/user/service/config.json', 'r') as f:
        data = json.load(f)
        if data.get('revoked', False):
            sys.exit(2) # Silently reject/exit

    if not os.path.isdir('/home/user/service/cache'):
        sys.exit(3) # Silently exit due to missing storage

    server = HTTPServer(('127.0.0.1', 8181), Handler)
    server.serve_forever()

if __name__ == '__main__':
    main()
EOF

    chmod +x /home/user/service/daemon.py

    chmod -R 777 /home/user
