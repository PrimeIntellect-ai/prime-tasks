#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl curl nmap rustc cargo
    pip3 install pytest

    mkdir -p /home/user/service
    cd /home/user/service

    # Generate self-signed cert
    openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Org/OU=IT/CN=admin-delta-7734" 2>/dev/null

    # Create Python server
    cat << 'EOF' > server.py
import ssl
from http.server import HTTPServer, BaseHTTPRequestHandler
import base64
import json

FLAG = "FLAG{jwt_n0n3_alg_m4ster_rust_8812}"

class JWTHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/flag':
            auth_header = self.headers.get('Authorization')
            if not auth_header or not auth_header.startswith('Bearer '):
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b"Missing or invalid token")
                return

            token = auth_header.split(' ')[1]
            parts = token.split('.')

            if len(parts) != 2 and len(parts) != 3:
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b"Invalid token format")
                return

            try:
                # Add padding back if necessary for base64 decode
                header_b64 = parts[0] + '=' * (-len(parts[0]) % 4)
                payload_b64 = parts[1] + '=' * (-len(parts[1]) % 4)

                header = json.loads(base64.urlsafe_b64decode(header_b64).decode('utf-8'))
                payload = json.loads(base64.urlsafe_b64decode(payload_b64).decode('utf-8'))

                if header.get('alg', '').lower() == 'none':
                    if payload.get('user') == 'admin-delta-7734' and payload.get('role') == 'admin':
                        self.send_response(200)
                        self.end_headers()
                        self.wfile.write(FLAG.encode('utf-8'))
                        return
            except Exception as e:
                pass

            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"Access Denied")
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not Found")

httpd = HTTPServer(('127.0.0.1', 8443), JWTHandler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile='cert.pem', keyfile='key.pem')
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
