#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git cargo curl build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /tmp/mock_servers
    cat << 'EOF' > /tmp/mock_servers/server_8080.py
from http.server import BaseHTTPRequestHandler, HTTPServer
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")
HTTPServer(('127.0.0.1', 8080), Handler).serve_forever()
EOF

    cat << 'EOF' > /tmp/mock_servers/server_8081.py
from http.server import BaseHTTPRequestHandler, HTTPServer
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(500)
        self.end_headers()
        self.wfile.write(b"ERROR")
HTTPServer(('127.0.0.1', 8081), Handler).serve_forever()
EOF

    echo "python3 /tmp/mock_servers/server_8080.py >/dev/null 2>&1 &" >> /home/user/.bashrc
    echo "python3 /tmp/mock_servers/server_8081.py >/dev/null 2>&1 &" >> /home/user/.bashrc
    echo "python3 /tmp/mock_servers/server_8080.py >/dev/null 2>&1 &" >> /root/.bashrc
    echo "python3 /tmp/mock_servers/server_8081.py >/dev/null 2>&1 &" >> /root/.bashrc

    chmod -R 777 /home/user
