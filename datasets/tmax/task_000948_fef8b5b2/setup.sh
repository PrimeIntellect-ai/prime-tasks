#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv git curl socat
    pip3 install pytest

    # Create vendored package
    mkdir -p /app/git-notifier-2.0.0/notifier

    cat << 'EOF' > /app/git-notifier-2.0.0/setup.py
from setuptools import setup, find_packages

setup(
    name="git-notifier",
    version="2.0.0",
    packages=find_packages(),
    entry_points={
        "console_scripts": [
            "git-notifier=notifier.server:main",
        ]
    }
)
EOF

    touch /app/git-notifier-2.0.0/notifier/__init__.py

    cat << 'EOF' > /app/git-notifier-2.0.0/notifier/server.py
import os
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        expected_token = os.environ.get("AUTH_TOKNE")
        auth_header = self.headers.get("Authorization")

        if not expected_token or auth_header != f"Bearer {expected_token}":
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b"Unauthorized\n")
            return

        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)

        try:
            data = json.loads(post_data)
            if data.get("event") == "push":
                print("Received push event")
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"OK\n")
            else:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Bad Request\n")
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"Internal Server Error\n")

def main():
    host = "0.0.0.0"
    port = 8000
    server = HTTPServer((host, port), RequestHandler)
    print(f"Starting server on {host}:{port}")
    server.serve_forever()

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
