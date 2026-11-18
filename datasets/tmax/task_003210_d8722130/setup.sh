#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl procps
pip3 install pytest

mkdir -p /home/user/server
cd /home/user/server

openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=ComplianceCorp/CN=internal-audit-mock"

cat << 'EOF' > server.py
import http.server
import ssl
import socketserver
import urllib.parse
import sys

class AuditHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline'")
            self.end_headers()
            self.wfile.write(b"Welcome to the mock service")
        elif self.path.startswith('/submit?'):
            query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            payload = query.get('q', [''])[0]
            if '<script>alert(1)</script>' in payload:
                self.send_response(200)
                self.send_header('Content-type', 'text/html')
                self.end_headers()
                self.wfile.write(f"Reflected: {payload}".encode())
            else:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Missing or invalid payload")
        else:
            self.send_response(404)
            self.end_headers()

PORT = 8443
httpd = socketserver.TCPServer(('127.0.0.1', PORT), AuditHandler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile="cert.pem", keyfile="key.pem")
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
EOF

useradd -m -s /bin/bash user || true

echo "pgrep -f server.py > /dev/null || (cd /home/user/server && python3 server.py &)" >> /home/user/.bashrc
echo "pgrep -f server.py > /dev/null || (cd /home/user/server && python3 server.py &)" >> /root/.bashrc

chmod -R 777 /home/user
