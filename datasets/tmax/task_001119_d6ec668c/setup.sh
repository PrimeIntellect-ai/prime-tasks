#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mock_systemd.py
import sys
import os
import subprocess
import time

if len(sys.argv) < 3 or sys.argv[1] != 'start':
    print("Usage: mock_systemd.py start <service_name>")
    sys.exit(1)

service_file = f"/home/user/{sys.argv[2]}"
if not os.path.exists(service_file):
    print(f"Service file {service_file} not found.")
    sys.exit(1)

exec_start = None
with open(service_file, 'r') as f:
    for line in f:
        if line.startswith('ExecStart='):
            exec_start = line.strip().split('=', 1)[1]

if not exec_start:
    print("No ExecStart found.")
    sys.exit(1)

print(f"Starting {exec_start}...")
proc = subprocess.Popen(exec_start, shell=True)
try:
    proc.wait()
except KeyboardInterrupt:
    proc.terminate()
EOF

    cat << 'EOF' > /home/user/webhook.service
[Unit]
Description=Webhook Service

[Service]
ExecStart=/usr/bin/python3 /home/user/webhook_service.py
Restart=always
EOF

    cat << 'EOF' > /home/user/webhook_service.py
import http.server
import ssl
import logging
import sys

# TODO: Fix logging to use RotatingFileHandler with maxBytes=1024, backupCount=3
logging.basicConfig(filename='/home/user/logs/webhook.log', level=logging.INFO)
logger = logging.getLogger(__name__)

class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Webhook Service Online\n")
        logger.info("Handled GET request")

def run():
    server_address = ('localhost', 8443)
    httpd = http.server.HTTPServer(server_address, WebhookHandler)

    # TODO: Configure TLS here using /home/user/certs/cert.pem and /home/user/certs/key.pem
    # httpd.socket = ssl.wrap_socket(httpd.socket, ... )

    logger.info("Starting server on port 8443")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()

if __name__ == '__main__':
    run()
EOF

    chmod -R 777 /home/user
