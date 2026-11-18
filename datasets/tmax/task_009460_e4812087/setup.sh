#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl curl nmap
    pip3 install pytest requests

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/passwords.txt
admin123
qwerty
password
letmein
rooster
sunflower
dragon
EOF
    chmod 644 /home/user/passwords.txt

    mkdir -p /home/user/service_keys
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/service_keys/key.pem -out /home/user/service_keys/cert.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=sec_auditor_99/CN=localhost"

    cat << 'EOF' > /tmp/mock_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import ssl
import base64
import json

class AuthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/admin':
            auth_header = self.headers.get('Authorization')
            if auth_header == 'Basic c2VjX2F1ZGl0b3JfOTk6cm9vc3Rlcg==': # base64 for sec_auditor_99:rooster
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"secret_token": "TOKEN_8a9b2c4d"}).encode())
            else:
                self.send_response(401)
                self.send_header('WWW-Authenticate', 'Basic realm="Admin"')
                self.end_headers()
                self.wfile.write(b'Unauthorized')
        else:
            self.send_response(404)
            self.end_headers()

httpd = HTTPServer(('127.0.0.1', 8427), AuthHandler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('/home/user/service_keys/cert.pem', '/home/user/service_keys/key.pem')
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
EOF

    chmod -R 777 /home/user
