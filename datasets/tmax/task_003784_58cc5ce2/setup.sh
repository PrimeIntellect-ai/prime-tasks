#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest pyinstaller

    mkdir -p /app

    # Create the vulnerable legacy service source
    cat << 'EOF' > /app/legacy_profile_svc.py
import http.server
import socketserver
import json
import base64
import sys

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/profile':
            auth_header = self.headers.get('Authorization')
            if not auth_header or not auth_header.startswith('Bearer '):
                self.send_response(401)
                self.end_headers()
                return
            token = auth_header.split(' ')[1]
            try:
                parts = token.split('.')
                if len(parts) != 3:
                    raise ValueError("Invalid JWT format")
                header_b64, payload_b64, sig = parts

                # Padding for base64 decode
                header_b64 += '=' * (-len(header_b64) % 4)
                payload_b64 += '=' * (-len(payload_b64) % 4)

                header = json.loads(base64.urlsafe_b64decode(header_b64).decode('utf-8'))
                payload = json.loads(base64.urlsafe_b64decode(payload_b64).decode('utf-8'))

                # Vulnerability: trusts alg: none without checking signature
                # For other algs, we just simulate acceptance for the test

                user = payload.get('user', 'unknown')
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                response = {"user": user, "ssn": "123-45-6789", "role": "user"}
                self.wfile.write(json.dumps(response).encode())
            except Exception as e:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(str(e).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", 9000), Handler) as httpd:
        httpd.serve_forever()
EOF

    # Compile it to a stripped binary
    cd /app
    pyinstaller --onefile --strip legacy_profile_svc.py
    mv dist/legacy_profile_svc /app/legacy_profile_svc
    rm -rf build dist legacy_profile_svc.spec legacy_profile_svc.py
    chmod +x /app/legacy_profile_svc

    # Setup user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
