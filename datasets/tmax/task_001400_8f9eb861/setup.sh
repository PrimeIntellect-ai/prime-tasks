#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    mkdir -p /home/user/dash_app
    mkdir -p /home/user/metrics_data

    cat << 'EOF' > /home/user/dash_app/dashboard.py
import http.server
import socketserver
import sys
import os

requests = 0

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        global requests
        if self.path == '/health':
            requests += 1
            if requests > 2:
                # Deliberate crash after 2 successful health checks
                os._exit(1)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

# Allow port reuse so supervisor can restart it quickly
class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

httpd = ReusableTCPServer(("127.0.0.1", 8080), Handler)
httpd.serve_forever()
EOF

    chmod +x /home/user/dash_app/dashboard.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
