#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv curl
    pip3 install pytest

    mkdir -p /app/auth_proxy-1.2.3/auth_proxy

    cat << 'EOF' > /app/auth_proxy-1.2.3/setup.py
from setuptools import setup, find_packages

setup(
    name="auth_proxy",
    version="1.2.3",
    packages=find_packages(),
    entry_points={
        "console_scripts": [
            "auth-proxy=auth_proxy.server:main"
        ]
    }
)
EOF

    touch /app/auth_proxy-1.2.3/auth_proxy/__init__.py

    cat << 'EOF' > /app/auth_proxy-1.2.3/auth_proxy/server.py
import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class AuthHandler(BaseHTTPRequestHandler):
    config_data = {}

    def do_GET(self):
        if self.path == '/api/whoami':
            auth_header = self.headers.get('Authorisation')
            if auth_header and auth_header.startswith('Bearer '):
                token = auth_header.split(' ')[1]
                users = self.config_data.get('users', [])
                for u in users:
                    if u.get('token') == token:
                        self.send_response(200)
                        self.send_header('Content-type', 'application/json')
                        self.end_headers()
                        response = {"username": u.get("username"), "group": u.get("group")}
                        self.wfile.write(json.dumps(response).encode())
                        return
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b'Unauthorized')
        else:
            self.send_response(404)
            self.end_headers()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--port', type=int, default=9090)
    parser.add_argument('--host', default='127.0.0.1')
    args = parser.parse_args()

    with open(args.config, 'r') as f:
        AuthHandler.config_data = json.load(f)

    server = HTTPServer((args.host, args.port), AuthHandler)
    server.serve_forever()

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
