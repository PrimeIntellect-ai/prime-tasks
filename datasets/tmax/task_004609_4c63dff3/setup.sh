#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest requests

    mkdir -p /home/user/investigation

    # Create and compile c2_agent.py
    cat << 'EOF' > /home/user/investigation/c2_agent.py
def authenticate_c2():
    c2_token = "C2-AUTH-99A8-XYZ2"
    return c2_token
EOF
    python3 -m py_compile /home/user/investigation/c2_agent.py
    mv /home/user/investigation/__pycache__/c2_agent.*.pyc /home/user/investigation/c2_agent.pyc
    rm /home/user/investigation/c2_agent.py

    # Create mock_server.py
    cat << 'EOF' > /home/user/mock_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/evidence':
            auth_header = self.headers.get('Authorization')
            if auth_header == 'Bearer C2-AUTH-99A8-XYZ2':
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"secret_flag": "FLAG{ev1d3nc3_r3c0v3r3d}"}')
            else:
                self.send_response(401)
                self.end_headers()

httpd = HTTPServer(('127.0.0.1', 8080), Handler)
httpd.serve_forever()
EOF

    # Create traffic.json
    cat << 'EOF' > /home/user/investigation/traffic.json
[
  {
    "domain": "bank.local",
    "original_csp": "default-src 'self'; script-src 'self' 'strict-dynamic';",
    "modified_csp": "default-src 'self'; script-src 'self' 'strict-dynamic' 'unsafe-inline';"
  },
  {
    "domain": "news.local",
    "original_csp": "default-src 'self'; script-src 'self';",
    "modified_csp": "default-src 'self'; script-src 'self';"
  },
  {
    "domain": "secure-vault.net",
    "original_csp": "default-src 'none'; script-src 'self';",
    "modified_csp": "default-src 'none';"
  }
]
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
