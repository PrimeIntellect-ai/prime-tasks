#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ curl
    pip3 install pytest

    mkdir -p /home/user/mock_containers/alpha/data
    mkdir -p /home/user/mock_containers/alpha/meta
    mkdir -p /home/user/mock_containers/beta/data
    mkdir -p /home/user/mock_containers/gamma/data
    mkdir -p /home/user/.config/reporter

    dd if=/dev/zero of=/home/user/mock_containers/alpha/data/part1.bin bs=1024 count=15 2>/dev/null
    dd if=/dev/zero of=/home/user/mock_containers/alpha/data/part2.bin bs=1024 count=5 2>/dev/null
    dd if=/dev/zero of=/home/user/mock_containers/alpha/meta/config.json bs=1024 count=2 2>/dev/null

    dd if=/dev/zero of=/home/user/mock_containers/beta/data/db.sqlite bs=1024 count=45 2>/dev/null

    dd if=/dev/zero of=/home/user/mock_containers/gamma/data/log.txt bs=1024 count=8 2>/dev/null

    cat << 'EOF' > /home/user/.config/reporter/auth.conf
# Client authentication config
TOKEN=invalid_default_token_999
EOF

    cat << 'EOF' > /home/user/reporting_service.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import os

EXPECTED_TOKEN = "secr3t_c4pacity_77"
EXPECTED_CSV = "alpha,20480\nbeta,46080\ngamma,8192\n"

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/upload':
            token = self.headers.get('X-Auth-Token')
            if token != EXPECTED_TOKEN:
                # Silently reject similar to anchor
                self.send_response(403)
                self.end_headers()
                return

            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length).decode('utf-8')

            if post_data.strip() == EXPECTED_CSV.strip():
                with open('/home/user/server_success.flag', 'w') as f:
                    f.write("SUCCESS")
                self.send_response(200)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(b"Metrics accepted")
            else:
                self.send_response(400)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 9090), RequestHandler)
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
