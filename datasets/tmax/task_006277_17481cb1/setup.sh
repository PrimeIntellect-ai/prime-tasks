#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest requests

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/microservice.py
import http.server
import socketserver
import json
import base64
import threading

class VulnerableHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/admin/rotate_secret':
            auth_header = self.headers.get('Authorization')
            if not auth_header or not auth_header.startswith('Bearer '):
                self.send_error(401, "Missing or invalid token")
                return

            token = auth_header.split(' ')[1]
            parts = token.split('.')
            if len(parts) < 2:
                self.send_error(401, "Malformed token")
                return

            try:
                # Padding fix
                header_padding = '=' * (4 - len(parts[0]) % 4)
                payload_padding = '=' * (4 - len(parts[1]) % 4)
                header = json.loads(base64.urlsafe_b64decode(parts[0] + header_padding).decode('utf-8'))
                payload = json.loads(base64.urlsafe_b64decode(parts[1] + payload_padding).decode('utf-8'))

                if header.get('alg', '').lower() != 'none':
                    self.send_error(403, "Invalid signature")
                    return

                if payload.get('role') != 'admin':
                    self.send_error(403, "Insufficient privileges")
                    return
            except Exception as e:
                self.send_error(400, "Token parse error")
                return

            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body)
                if data.get('recovery_pin') == "8429":
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    response = {"status": "success", "confirmation": "ROTATED_8429_SUCCESS"}
                    self.wfile.write(json.dumps(response).encode())
                else:
                    self.send_error(401, "Invalid PIN")
            except:
                self.send_error(400, "Bad Request")
        else:
            self.send_error(404, "Not Found")

    def log_message(self, format, *args):
        pass # Suppress logging

PORT = 5000
handler = VulnerableHandler
httpd = socketserver.TCPServer(("127.0.0.1", PORT), handler)

def serve():
    httpd.serve_forever()

thread = threading.Thread(target=serve, daemon=True)
thread.start()

import time
time.sleep(999999)
EOF

# Ensure the microservice starts when a bash session is opened
echo "nohup python3 /home/user/microservice.py > /dev/null 2>&1 &" >> /home/user/.bashrc
echo "sleep 1" >> /home/user/.bashrc

chmod -R 777 /home/user
