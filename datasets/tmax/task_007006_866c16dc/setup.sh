#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/logs

    cat << 'EOF' > /home/user/app/users.json
{
  "admin": {
    "password": "admin_pass",
    "role": "admin"
  },
  "guest": {
    "password": "guest_pass",
    "role": "viewer"
  }
EOF

    cat << 'EOF' > /home/user/app/auth_service.py
import json
import logging
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.request

# TODO: Agent needs to change this to TimedRotatingFileHandler
logging.basicConfig(
    handlers=[logging.FileHandler('/home/user/app/logs/auth.log')],
    level=logging.INFO,
    format='%(asctime)s - %(message)s'
)

with open('/home/user/app/users.json', 'r') as f:
    USERS = json.load(f)

TOKENS = {}

class AuthHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)

        if self.path == '/login':
            data = json.loads(post_data)
            user = data.get('username')
            if user in USERS and USERS[user]['password'] == data.get('password'):
                token = f"tok_{user}"
                TOKENS[token] = user
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps({"token": token}).encode())
                logging.info(f"Login success: {user}")
            else:
                self.send_response(401)
                self.end_headers()

        elif self.path == '/trigger':
            auth_header = self.headers.get('Authorization', '')
            if auth_header.startswith('Bearer '):
                token = auth_header.split(' ')[1]
                if token in TOKENS:
                    user = TOKENS[token]
                    # TODO: Agent needs to change X-Forwarded-User to the correct internal header
                    req = urllib.request.Request('http://localhost:8082/build', method='POST')
                    req.add_header('X-Forwarded-User', user)
                    try:
                        resp = urllib.request.urlopen(req)
                        self.send_response(200)
                        self.end_headers()
                        self.wfile.write(resp.read())
                    except Exception as e:
                        self.send_response(500)
                        self.end_headers()
                    return
            self.send_response(401)
            self.end_headers()

if __name__ == '__main__':
    HTTPServer(('localhost', 8081), AuthHandler).serve_forever()
EOF

    cat << 'EOF' > /home/user/app/data_service.py
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class DataHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/build':
            user = self.headers.get('X-Internal-User')
            if user:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps({"status": "success", "build_id": f"build_for_{user}"}).encode())
            else:
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b"Missing internal routing header")

if __name__ == '__main__':
    HTTPServer(('localhost', 8082), DataHandler).serve_forever()
EOF

    chmod -R 777 /home/user
