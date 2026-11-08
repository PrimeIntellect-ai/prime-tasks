#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl jq socat netcat-openbsd
    pip3 install pytest

    mkdir -p /home/user/logs_pool
    mkdir -p /home/user/api

    # Create mock log files
    dd if=/dev/zero of=/home/user/logs_pool/db_backup.log bs=1024 count=2048
    dd if=/dev/zero of=/home/user/logs_pool/web_access.log bs=1024 count=1024
    dd if=/dev/zero of=/home/user/logs_pool/syslog.log bs=1024 count=512

    # Create the Python API server
    cat << 'EOF' > /home/user/api/server.py
import http.server
import json
import time

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'OK')
        elif self.path.startswith('/tier/'):
            filename = self.path.split('/')[-1]
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            if filename in ['db_backup.log', 'syslog.log']:
                self.wfile.write(json.dumps({"tier": "archive"}).encode())
            else:
                self.wfile.write(json.dumps({"tier": "retain"}).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    # Simulate boot delay
    time.sleep(3)
    server = http.server.HTTPServer(('localhost', 9090), Handler)
    server.serve_forever()
EOF
    chmod +x /home/user/api/server.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
