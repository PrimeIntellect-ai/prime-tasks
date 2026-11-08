#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tar
    pip3 install pytest

    mkdir -p /home/user/src/bin /home/user/src/config

    cat << 'EOF' > /home/user/src/bin/server.py
#!/usr/bin/env python3
import configparser
import http.server
import socketserver
import os
import sys

config_path = os.path.join(os.path.dirname(__file__), '../config/worker.ini')
config = configparser.ConfigParser()
config.read(config_path)

try:
    port = int(config['Service']['Port'])
except KeyError:
    sys.exit(1)

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

with socketserver.TCPServer(("127.0.0.1", port), Handler) as httpd:
    httpd.serve_forever()
EOF

    chmod +x /home/user/src/bin/server.py

    cat << 'EOF' > /home/user/src/config/worker.ini
[Unit]
Description=Mock Worker

[Service]
Port=8080
EOF

    cd /home/user/src && tar -czf /home/user/source.tar.gz bin config
    cd / && rm -rf /home/user/src

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
