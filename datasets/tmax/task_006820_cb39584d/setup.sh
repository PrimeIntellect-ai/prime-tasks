#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/logs
    cat << 'EOF' > /home/user/app/logs/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 +0000] "GET /api/status HTTP/1.1" 200 15
192.168.1.12 - - [10/Oct/2023:13:56:01 +0000] "GET /api/data?token=Bearer aB3dE5fG7hI9jK1lM3nO5pQ7rS9tU1vW HTTP/1.1" 200 1024
192.168.1.15 - - [10/Oct/2023:13:57:12 +0000] "POST /api/upload HTTP/1.1" 201 45
EOF

    cat << 'EOF' > /home/user/mock_auth_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class AuthHandler(BaseHTTPRequestHandler):
    active_token = "aB3dE5fG7hI9jK1lM3nO5pQ7rS9tU1vW"

    def do_POST(self):
        if self.path == '/api/rotate':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data.decode('utf-8'))
                if data.get('old_token') == self.__class__.active_token:
                    self.__class__.active_token = data.get('new_token')
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    self.wfile.write(b'{"status": "rotated"}')
                else:
                    self.send_response(403)
                    self.end_headers()
                    self.wfile.write(b'{"status": "forbidden"}')
            except Exception:
                self.send_response(400)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        if self.path == '/api/verify':
            auth_header = self.headers.get('Authorization')
            if auth_header == f"Bearer {self.__class__.active_token}":
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"authenticated": true}')
            else:
                self.send_response(401)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"authenticated": false}')
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 9090), AuthHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /etc/profile.d/start_server.sh
if ! pgrep -f mock_auth_server.py > /dev/null; then
    python3 /home/user/mock_auth_server.py &
    sleep 1
fi
EOF

    echo 'if ! pgrep -f mock_auth_server.py > /dev/null; then python3 /home/user/mock_auth_server.py & sleep 1; fi' >> /home/user/.bashrc
    echo 'if ! pgrep -f mock_auth_server.py > /dev/null; then python3 /home/user/mock_auth_server.py & sleep 1; fi' >> /root/.bashrc

    chmod -R 777 /home/user
