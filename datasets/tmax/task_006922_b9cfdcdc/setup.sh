#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang openssh-server openssh-client curl
pip3 install pytest

mkdir -p /home/user/proxy

cat << 'EOF' > /home/user/backend.py
import http.server
import json

class MetricsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"cpu_usage": 95, "memory_usage": 45}).encode())
        else:
            self.send_response(404)
            self.end_headers()

http.server.HTTPServer(('127.0.0.1', 8080), MetricsHandler).serve_forever()
EOF

cat << 'EOF' > /home/user/smtp_server.py
import smtpd
import asyncore

class CustomSMTPServer(smtpd.SMTPServer):
    def process_message(self, peer, mailfrom, rcpttos, data, **kwargs):
        with open("/home/user/proxy/email_received.log", "a") as f:
            f.write(f"FROM:{mailfrom} TO:{','.join(rcpttos)} DATA:{data.decode('utf-8')}\n")

server = CustomSMTPServer(('127.0.0.1', 1025), None)
asyncore.loop()
EOF

mkdir -p /run/sshd

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
