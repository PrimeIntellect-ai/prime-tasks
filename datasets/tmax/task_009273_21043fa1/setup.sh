#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bubblewrap procps
    pip3 install pytest

    # Create the server script
    cat << 'EOF' > /tmp/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class SimpleServer(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/login':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data)
            except json.JSONDecodeError:
                data = {}
            if data.get('user') == 'auditor' and data.get('pass') == 'audit123':
                self.send_response(200)
                self.send_header('Set-Cookie', 'session_token=valid_token_8899; Path=/; Secure')
                self.end_headers()
                self.wfile.write(b'Success')
            else:
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b'Unauthorized')
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        if self.path == '/secure_data.txt':
            cookie = self.headers.get('Cookie', '')
            if 'session_token=valid_token_8899' in cookie:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'COMPLIANCE_CONFIDENTIAL_DATA_9921')
            else:
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b'Forbidden')
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server_address = ('127.0.0.1', 8080)
    httpd = HTTPServer(server_address, SimpleServer)
    httpd.serve_forever()
EOF

    # Ensure the server starts when the container is run/exec'd
    mkdir -p /.singularity.d/env
    cat << 'EOF' > /.singularity.d/env/99-server.sh
#!/bin/sh
if ! pgrep -f "/tmp/server.py" > /dev/null; then
    python3 /tmp/server.py > /dev/null 2>&1 &
    sleep 1
fi
EOF
    chmod +x /.singularity.d/env/99-server.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
