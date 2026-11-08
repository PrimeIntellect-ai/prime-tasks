#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest pexpect requests

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_wizard.py
#!/usr/bin/env python3
import sys
import time

def prompt(text):
    print(text, end='', flush=True)
    return sys.stdin.readline().strip()

print("Starting configuration wizard...")
time.sleep(0.5)
env = prompt("Environment Name: ")
time.sleep(0.5)
port = prompt("Port Number: ")

with open('/home/user/app.conf', 'w') as f:
    f.write(f"ENV={env}\nPORT={port}\n")

print("Configuration saved to app.conf.")
EOF
    chmod +x /home/user/config_wizard.py

    cat << 'EOF' > /home/user/server.py
#!/usr/bin/env python3
import os
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

env = "unknown"
port = 8000

if os.path.exists('/home/user/app.conf'):
    with open('/home/user/app.conf', 'r') as f:
        for line in f:
            if line.startswith('ENV='):
                env = line.strip().split('=')[1]
            elif line.startswith('PORT='):
                port = int(line.strip().split('=')[1])

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {"status": "ok", "environment": env}
            self.wfile.write(json.dumps(response).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass

if __name__ == '__main__':
    server = HTTPServer(('localhost', port), HealthHandler)
    server.serve_forever()
EOF
    chmod +x /home/user/server.py

    chmod -R 777 /home/user
