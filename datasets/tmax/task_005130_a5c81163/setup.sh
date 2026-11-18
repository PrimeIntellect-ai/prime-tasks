#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat curl logrotate tar
    pip3 install pytest

    mkdir -p /home/user/infra_project

    cat << 'EOF' > /home/user/infra_project/server.py
import http.server
import socketserver
import json
import sys
import os

PORT = 8080
DATA_FILE = "/home/user/infra_project/data/data.json"

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"healthy")
        elif self.path == '/api/data':
            if os.path.exists(DATA_FILE):
                with open(DATA_FILE, 'r') as f:
                    data = f.read()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(data.encode())
            else:
                self.send_response(404)
                self.end_headers()
        elif self.path == '/crash':
            sys.exit(1)
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    mkdir -p /tmp/setup_data/data
    echo '{"status": "recovered"}' > /tmp/setup_data/data/data.json
    cd /tmp/setup_data
    tar -czvf /home/user/infra_project/backup.tar.gz data/data.json
    rm -rf /tmp/setup_data

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
