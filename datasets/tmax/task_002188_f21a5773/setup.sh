#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git curl
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup vendored package
    mkdir -p /app/vendored/geomath
    cat << 'EOF' > /app/vendored/geomath/core.py
def compute_series(n):
    return n * compute_series(n - 1)
EOF
    touch /app/vendored/geomath/__init__.py

    # Setup geo_api repo
    mkdir -p /home/user/geo_api
    cd /home/user/geo_api

    git init
    git config user.name "Previous Developer"
    git config user.email "dev@example.com"

    # Commit 1: Initial commit
    echo -n "sec_r3t_9942xyz" > token.key

    cat << 'EOF' > processor.py
import sys
sys.path.append('/app/vendored/geomath')
from core import compute_series

def process_data(coords):
    processed_coords = [float(c) for c in coords]
    val = compute_series(5)
    return processed_coords + [val]
EOF

    cat << 'EOF' > server.py
import http.server
import socketserver
import json
import os
from processor import process_data

PORT = 8080

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/process':
            if not os.path.exists('token.key'):
                self.send_response(500)
                self.end_headers()
                return
            with open('token.key', 'r') as f:
                token = f.read().strip()

            auth_header = self.headers.get('Authorization')
            if auth_header != f"Bearer {token}":
                self.send_response(401)
                self.end_headers()
                return

            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            payload = json.loads(post_data)

            result = process_data(payload["coords"])

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"result": result}).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == "__main__":
    with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
        httpd.serve_forever()
EOF

    git add .
    git commit -m "Initial commit"

    # Commit 2: Delete token
    rm token.key
    git add -u
    git commit -m "Remove secret token from repo"

    # Commit 3: Refactor
    echo "# Refactored" >> processor.py
    git add processor.py
    git commit -m "Refactor processor"

    # Commit 4: Regression
    cat << 'EOF' > processor.py
import sys
sys.path.append('/app/vendored/geomath')
from core import compute_series

def process_data(coords):
    # Regression: Rounding coordinates causes precision loss
    processed_coords = [round(c, 2) for c in coords]
    val = compute_series(5)
    return processed_coords + [val]
EOF
    git add processor.py
    git commit -m "Optimize coordinate payload size"

    # Commit 5: Update server bindings
    echo "# Update server bindings" >> server.py
    git add server.py
    git commit -m "Update server bindings"

    chmod -R 777 /home/user
    chmod -R 777 /app
