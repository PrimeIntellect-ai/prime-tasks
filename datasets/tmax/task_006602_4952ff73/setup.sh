#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

SECRET_TOKEN = "FLG_77b31_s3cr3t"

class AuthHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/login':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)

            # Auth bypass vulnerability
            if self.headers.get('X-Admin-Bypass') == 'true':
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"status": "success", "secret_token": SECRET_TOKEN}).encode())
                return

            self.send_response(401)
            self.end_headers()
            self.wfile.write(b'Unauthorized')

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), AuthHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/app.log
[INFO] 2023-10-01 10:00:00 - User registered: Alice Smith. Email: alice.smith@example.com, SSN: 123-45-6789.
[DEBUG] 2023-10-01 10:05:00 - Failed login attempt for bob_jones@domain.co.uk.
[INFO] 2023-10-01 10:10:00 - Payment processed for Charlie. SSN: 987-65-4321, email: charlie+test@sub.domain.org.
EOF

    chmod -R 777 /home/user
