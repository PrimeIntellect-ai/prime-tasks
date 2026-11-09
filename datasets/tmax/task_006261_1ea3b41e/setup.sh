#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import base64

FLAG = "FLAG{jwt_n0n3_alg_byp4ss_5ucc3ss}"

def base64url_decode(input):
    rem = len(input) % 4
    if rem > 0:
        input += '=' * (4 - rem)
    return base64.urlsafe_b64decode(input)

class SimpleServer(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/login':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            # standard token for 'guest'
            token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiZ3Vlc3QifQ.SIGNATURE"
            self.wfile.write(json.dumps({"token": token}).encode())

        elif self.path == '/admin/flag':
            auth_header = self.headers.get('Authorization')
            if not auth_header or not auth_header.startswith('Bearer '):
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b"Unauthorized")
                return

            token = auth_header.split(' ')[1]
            parts = token.split('.')
            if len(parts) != 3:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Malformed token")
                return

            try:
                header = json.loads(base64url_decode(parts[0]))
                payload = json.loads(base64url_decode(parts[1]))

                # VULNERABILITY: Accepts 'none' algorithm
                if header.get('alg', '').lower() == 'none':
                    if payload.get('role') == 'admin':
                        self.send_response(200)
                        self.end_headers()
                        self.wfile.write(FLAG.encode())
                        return
                    else:
                        self.send_response(403)
                        self.end_headers()
                        self.wfile.write(b"Forbidden: Admins only")
                        return
                else:
                    self.send_response(401)
                    self.end_headers()
                    self.wfile.write(b"Invalid signature")
                    return
            except Exception as e:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Error parsing token")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), SimpleServer)
    server.serve_forever()
EOF

    echo "python3 /home/user/server.py &" >> /home/user/.bashrc

    chown -R user:user /home/user
    chmod -R 777 /home/user
