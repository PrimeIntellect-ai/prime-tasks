#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl openssh-client gawk coreutils procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/compliance
    mkdir -p /home/user/.ssh

    cat << 'EOF' > /home/user/app/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

class VulnHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == '/login':
            qs = parse_qs(parsed.query)
            url = qs.get('url', ['/'])[0]
            self.send_response(302)
            separator = '&' if '?' in url else '?'
            self.send_header('Location', f"{url}{separator}token=SECURE_COMPLIANCE_99812")
            self.end_headers()
        else:
            self.send_response(200)
            self.end_headers()

if __name__ == '__main__':
    HTTPServer(('127.0.0.1', 8080), VulnHandler).serve_forever()
EOF

    sha256sum /home/user/app/server.py | awk '{print $1}' > /home/user/compliance/baseline.sha256

    # Ensure the server starts when a shell is opened
    echo "pgrep -f 'python3 /home/user/app/server.py' > /dev/null || python3 /home/user/app/server.py &" >> /home/user/.bashrc
    echo "pgrep -f 'python3 /home/user/app/server.py' > /dev/null || python3 /home/user/app/server.py &" >> /root/.bashrc

    chmod -R 777 /home/user
    chmod 700 /home/user/.ssh
