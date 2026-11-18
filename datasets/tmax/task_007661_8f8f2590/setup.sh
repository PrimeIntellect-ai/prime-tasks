#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest requests

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app

    openssl req -x509 -newkey rsa:2048 -keyout /home/user/app/key.pem -out /home/user/app/cert.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Company/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

    cat << 'EOF' > /home/user/app/server.py
import ssl
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class SimpleSecServer(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/public/../../../etc/passwd":
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"Forbidden")
        else:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")

    def do_POST(self):
        if self.path == "/api/auth":
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b"Unauthorized")
        else:
            self.send_response(404)
            self.end_headers()

httpd = HTTPServer(('127.0.0.1', 8443), SimpleSecServer)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('/home/user/app/cert.pem', '/home/user/app/key.pem')
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
EOF

    chmod -R 777 /home/user
