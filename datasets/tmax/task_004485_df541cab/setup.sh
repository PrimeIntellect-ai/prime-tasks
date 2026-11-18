#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv curl
pip3 install pytest

mkdir -p /home/user/legacy_service
mkdir -p /home/user/ci_pipeline

cat << 'EOF' > /home/user/legacy_service/setup.sh
#!/bin/bash
echo "Starting Legacy Service Interactive Setup..."
read -p "Enter Admin Username: " user
read -p "Enter Admin Password: " pass
read -p "Enter Service Port: " port
read -p "Enter Configuration Token: " token

cat << JSON > /home/user/legacy_service/config.json
{
  "user": "$user",
  "pass": "$pass",
  "port": $port,
  "token": "$token"
}
JSON
echo "Setup complete. Configuration saved."
EOF
chmod +x /home/user/legacy_service/setup.sh

cat << 'EOF' > /home/user/legacy_service/daemon.py
#!/usr/bin/env python3
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

CONFIG_FILE = '/home/user/legacy_service/config.json'

if not os.path.exists(CONFIG_FILE):
    print("Error: config.json not found. Run setup.sh first.")
    sys.exit(1)

with open(CONFIG_FILE, 'r') as f:
    config = json.load(f)

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {"status": "ok", "service": "legacy", "token": config.get("token")}
            self.wfile.write(json.dumps(response).encode())
        else:
            self.send_response(404)
            self.end_headers()

def run():
    port = int(config.get("port", 8080))
    server_address = ('127.0.0.1', port)
    httpd = HTTPServer(server_address, HealthHandler)
    print(f"Starting daemon on port {port}...")
    httpd.serve_forever()

if __name__ == '__main__':
    run()
EOF
chmod +x /home/user/legacy_service/daemon.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
