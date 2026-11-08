#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user
    # 1. Create Certificates
    openssl req -x509 -nodes -newkey rsa:2048 -keyout ca.key -out ca.crt -days 365 -subj "/CN=Internal-Root-CA"
    openssl req -nodes -newkey rsa:2048 -keyout server.key -out server.csr -subj "/CN=secure-rotation-endpoint.local"
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365

    # 2. Create the legacy pyc file
    cat << 'EOF' > auth_handler.py
def get_legacy_key():
    secret = "legacy_admin_token_xyz789"
    return secret
EOF
    python3 -m py_compile auth_handler.py
    mv __pycache__/auth_handler.*.pyc auth_handler.pyc
    rm auth_handler.py

    # 3. Create the HTTPS server script
    cat << 'EOF' > server.py
import http.server
import ssl
import json
from http.cookies import SimpleCookie

class RotationHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != '/rotate':
            self.send_response(404)
            self.end_headers()
            return

        auth_header = self.headers.get('Authorization')
        if auth_header != 'Bearer legacy_admin_token_xyz789':
            self.send_response(401)
            self.end_headers()
            return

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)

        try:
            data = json.loads(body)
            if data.get('new_key') != 'secure_new_key_2024':
                raise ValueError
        except:
            self.send_response(400)
            self.end_headers()
            return

        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.send_header('Set-Cookie', 'session_token=rotated_successfully_abc123; HttpOnly; Secure')
        self.end_headers()
        self.wfile.write(b'{"status": "success"}')

httpd = http.server.HTTPServer(('127.0.0.1', 8443), RotationHandler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile='/home/user/server.crt', keyfile='/home/user/server.key')
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
EOF

    chmod -R 777 /home/user
