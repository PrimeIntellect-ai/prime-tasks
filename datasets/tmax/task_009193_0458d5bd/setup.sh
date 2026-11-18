#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/nginx.conf
events {
    worker_connections 1024;
}
http {
    access_log /home/user/app/access.log;
    error_log /home/user/app/error.log;
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:9090;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/backend.py
import http.server
import socketserver
import sys

# Bug: Hardcoded port instead of using arguments or matching Nginx
PORT = 8000

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Backend Active")

with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/app/monitor.py
import subprocess
import time

def run():
    while True:
        # Bug: Not passing the port argument or environment variable if backend was updated to expect it
        p = subprocess.Popen(["python3", "/home/user/app/backend.py"])
        p.wait()
        time.sleep(1)

if __name__ == "__main__":
    run()
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
