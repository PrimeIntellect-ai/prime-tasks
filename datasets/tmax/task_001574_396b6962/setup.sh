#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    # 1. Create and compile the legacy ELF binary
    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
int main() {
    const char* secret = "OLD_API_KEY=8f9a2b4c6d8e0f1";
    printf("Legacy Auth Client Running...\n");
    return 0;
}
EOF
    gcc /tmp/legacy.c -o /home/user/legacy_auth_client
    rm /tmp/legacy.c

    # 2. Create the vulnerable Python script
    cat << 'EOF' > /home/user/auth_handler.py
import hashlib

def hash_password(password):
    # Vulnerable to collision attacks and extremely fast to brute force
    hasher = hashlib.md5()
    hasher.update(password.encode('utf-8'))
    return hasher.hexdigest()

def verify_password(stored_hash, password):
    return stored_hash == hash_password(password)
EOF

    # 3. Create the local rotation server
    cat << 'EOF' > /home/user/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class RotationHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/auth':
            if self.headers.get('X-Old-Key') == '8f9a2b4c6d8e0f1':
                self.send_response(200)
                self.send_header('Set-Cookie', 'session_id=valid_session_xyz987')
                self.end_headers()
                self.wfile.write(b"Authenticated")
            else:
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b"Forbidden")
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/rotate':
            cookie = self.headers.get('Cookie', '')
            if 'session_id=valid_session_xyz987' in cookie:
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                response = {
                    "new_key": "n3w_s3cur3_k3y_2024",
                    "sha256_checksum": "20bf21e78696abfe0af6ed0ffc5a968600d892ba9e5cc09dd4338575a61099e0"
                }
                self.wfile.write(json.dumps(response).encode())
            else:
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b"Unauthorized")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), RotationHandler)
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
