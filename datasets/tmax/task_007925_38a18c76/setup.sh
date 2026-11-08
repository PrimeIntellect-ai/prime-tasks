#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx
    pip3 install pytest requests semver

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/versions.txt
libA-0.9.5
libA-1.0.12
libA-1.1.9
libA-1.2.9
libA-1.3.0-alpha
libA-2.0.1
libB-1.5.0
EOF

    cat << 'EOF' > /home/user/project/legacy_config.b64
UE9SVD05MDkwCk1PREU9cHJvZHVjdGlvbgpEQj1zcWxpdGUK
EOF

    cat << 'EOF' > /home/user/project/backend.py
import json
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            with open('/home/user/project/config.json', 'r') as f:
                data = json.load(f)
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(data).encode('utf-8'))
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(e).encode('utf-8'))

if __name__ == '__main__':
    print("Starting backend on 9090...")
    HTTPServer(('127.0.0.1', 9090), Handler).serve_forever()
EOF

    chmod -R 777 /home/user
