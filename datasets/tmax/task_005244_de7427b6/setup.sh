#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx systemd cron curl
    pip3 install pytest

    # 1. Setup NGINX Backup and Corrupted Config
    mkdir -p /var/backups/nginx/
    cat << 'EOF' > /var/backups/nginx/default.bak
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:8080;
    }
}
EOF

    cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    # Corrupted configuration
    location / {
        proxy_pass http://127.0.0.1:9999;
    }
}
EOF

    # 2. Setup Backend Service (Vendored Package)
    mkdir -p /app/py-mail-processor-1.2.0/
    cat << 'EOF' > /app/py-mail-processor-1.2.0/server.py
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'OK\n')
        else:
            self.send_response(404)
            self.end_headers()

port = int(os.environ.get('PORT', 9090))
server = HTTPServer(('127.0.0.1', port), RequestHandler)
server.serve_forever()
EOF

    cat << 'EOF' > /etc/systemd/system/mail-receiver.service
[Unit]
Description=Mail Receiver Service

[Service]
ExecStart=/usr/bin/python3 /app/py-mail-processor-1.2.0/server.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    touch /var/log/mail-receiver.log

    # 3. Setup Oracle Filter
    cat << 'EOF' > /app/oracle_filter
#!/usr/bin/env python3
import sys
import re

def main():
    line = sys.stdin.readline()
    sanitized = re.sub(r'[^a-zA-Z0-9 \-]', '', line)
    print(sanitized, end='')

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_filter

    # 4. Create user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/backups

    chmod -R 777 /home/user
