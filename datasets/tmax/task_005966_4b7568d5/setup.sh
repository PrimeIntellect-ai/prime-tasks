#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit

    cat << 'EOF' > /home/user/audit/wordlist.txt
admin123
password
letmein12
secr3t_vault!
qwerty
appserver
hunter2
EOF

    echo "586f2b450cf2aee379c6b32a76f2f01f82f2dbf77c3a0ec2b2600ba451ef92d5" > /home/user/audit/target.hash

    cat << 'EOF' > /home/user/audit/auth_gen.py
import sys
import hashlib
if len(sys.argv) != 2:
    print("Usage: python3 auth_gen.py <password>")
    sys.exit(1)
pw = sys.argv[1]
# Simple salted token generation for the task
token = hashlib.md5((pw + "_salt123").encode()).hexdigest()
print(f"TOKEN={token}")
EOF

    cat << 'EOF' > /home/user/audit/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import os

class SimpleServer(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        # VULNERABILITY: Missing CSP headers
        self.end_headers()
        token = os.environ.get('AUTH_TOKEN', 'missing')
        self.wfile.write(b"<html><body><h1>Hello! Token is " + token.encode() + b"</h1></body></html>")

if __name__ == "__main__":
    server = HTTPServer(('127.0.0.1', 8080), SimpleServer)
    server.serve_forever()
EOF

    chown -R user:user /home/user/audit
    chmod -R 777 /home/user
