#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip supervisor curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/analytics_service.py
import http.server
import socketserver
import sys

class AnalyticsHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b"ANALYTICS_COST_SAVINGS_ACTIVE")

if __name__ == "__main__":
    with socketserver.TCPServer(("127.0.0.1", 9090), AnalyticsHandler) as httpd:
        httpd.serve_forever()
EOF
    chmod +x /home/user/analytics_service.py

    touch /home/user/.bashrc

    chmod -R 777 /home/user
