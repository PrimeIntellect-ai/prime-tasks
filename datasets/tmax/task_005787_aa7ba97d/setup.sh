#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest requests

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/passwords.txt
apple
battery
charlie
dragon
elephant
falcon
EOF

    cat << 'EOF' > /home/user/server.py
import http.server
import socketserver
import base64
import urllib.parse

PORT = 5000
KEY = b'sec'
ADMIN_PASS = 'charlie'

def xor_crypt(data, key):
    return bytes([data[i] ^ key[i % len(key)] for i in range(len(data))])

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/login':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length).decode('utf-8')
            params = urllib.parse.parse_qs(post_data)
            if params.get('username', [''])[0] == 'admin' and params.get('password', [''])[0] == ADMIN_PASS:
                plaintext = b'user=admin&role=standard'
                ciphertext = xor_crypt(plaintext, KEY)
                cookie = base64.b64encode(ciphertext).decode('utf-8')
                self.send_response(200)
                self.send_header('Set-Cookie', f'session={cookie}')
                self.end_headers()
                self.wfile.write(b"Logged in")
            else:
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b"Failed")
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    # Ensure the server starts when a shell is opened if it's not already running
    cat << 'EOF' >> /home/user/.bashrc
if ! pgrep -f "python3 /home/user/server.py" > /dev/null; then
    python3 /home/user/server.py > /dev/null 2>&1 &
    sleep 1
fi
EOF

    # Also add to system-wide bashrc for non-interactive shells
    cat << 'EOF' >> /etc/bash.bashrc
if ! pgrep -f "python3 /home/user/server.py" > /dev/null; then
    python3 /home/user/server.py > /dev/null 2>&1 &
    sleep 1
fi
EOF

    chmod -R 777 /home/user
