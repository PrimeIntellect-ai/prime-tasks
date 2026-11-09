#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest requests

    mkdir -p /home/user/app
    cd /home/user/app

    # Generate self-signed cert
    openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=localhost" 2>/dev/null

    # Create server.py
    cat << 'EOF' > server.py
import http.server
import ssl
import sys

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"OK")
        elif self.path == '/crash':
            sys.exit(1)
        else:
            self.send_response(404)
            self.end_headers()

httpd = http.server.HTTPServer(('127.0.0.1', 8443), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile='cert.pem', keyfile='key.pem')
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

try:
    httpd.serve_forever()
except KeyboardInterrupt:
    pass
EOF
    chmod +x server.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
