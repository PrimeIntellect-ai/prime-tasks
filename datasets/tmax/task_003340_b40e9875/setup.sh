#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-client curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/keys /home/user/.ssh
    chmod 700 /home/user/.ssh
    echo -n "super_secret_devsecops_key_99" > /home/user/keys/secret.key
    chmod 600 /home/user/keys/secret.key

    cat << 'EOF' > /home/user/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer

class InsecureHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.send_header("X-XSS-Protection", "1; mode=block")
        self.end_headers()
        self.wfile.write(b"Hello World")

    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.send_header("X-XSS-Protection", "1; mode=block")
        self.end_headers()

if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 8080), InsecureHandler)
    server.serve_forever()
EOF

    # Add to bashrc so it starts when an interactive shell is opened
    echo "python3 /home/user/server.py &" >> /home/user/.bashrc
    echo "python3 /home/user/server.py &" >> /root/.bashrc

    chmod -R 777 /home/user
