#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libcurl4-openssl-dev libssl-dev sudo curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import time
import ctypes
import re

try:
    libc = ctypes.CDLL("libc.so.6")
except OSError:
    libc = None

def get_expected_pin():
    if not libc: return "000000"
    current_minute = int(time.time()) // 60
    libc.srand(current_minute)
    pin = libc.rand() % 1000000
    return f"{pin:06d}"

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/flag':
            cookie = self.headers.get('Cookie', '')
            integrity = self.headers.get('X-Integrity-Check', '')

            with open("/home/user/server.log", "a") as logf:
                logf.write(f"HASH: {integrity}\n")

            if not libc:
                correct_pin = "000000"
            else:
                current_minute = int(time.time()) // 60
                libc.srand(current_minute)
                correct_pin = str(libc.rand() % 1000000)

            if f"auth_pin={correct_pin}" in cookie and re.match(r'^[a-f0-9]{64}$', integrity):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"FLAG{c_evasi0n_m4st3r}")
            else:
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b"Forbidden")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8000), RequestHandler)
    server.serve_forever()
EOF

    chown user:user /home/user/server.py

    # Ensure server starts when bash is invoked
    echo "nohup python3 /home/user/server.py > /home/user/server_out.log 2>&1 &" >> /home/user/.bashrc
    echo "nohup python3 /home/user/server.py > /home/user/server_out.log 2>&1 &" >> /root/.bashrc

    chmod -R 777 /home/user
