#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl procps
    pip3 install pytest requests PyJWT

    # Generate self-signed certificate
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/server.key -out /tmp/server.crt -days 365 -nodes -subj "/CN=DevSecOpsLocal/O=TestAuth"

    # Create the Python server script
    cat << 'EOF' > /tmp/server.py
import http.server
import ssl
import json

class SecureHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        auth_header = self.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            self.send_response(401)
            self.end_headers()
            return

        if self.path == '/api/health':
            self.send_response(200)
            # Intentional policy violations: Missing Strict-Transport-Security and Content-Security-Policy
            self.send_header('Content-type', 'application/json')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Server', 'TestAPI/1.0')
            self.end_headers()
            self.wfile.write(b'{"status": "healthy"}')
        else:
            self.send_response(404)
            self.end_headers()

httpd = http.server.HTTPServer(('127.0.0.1', 8443), SecureHandler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile='/tmp/server.crt', keyfile='/tmp/server.key')
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
EOF

    # Ensure the background server starts when a shell is opened
    echo 'if ! pgrep -f "python3 /tmp/server.py" > /dev/null; then python3 /tmp/server.py & sleep 2; fi' >> /etc/bash.bashrc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
