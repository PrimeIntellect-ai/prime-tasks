#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ curl
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/access.log
127.0.0.1 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326
127.0.0.1 - - [10/Oct/2023:13:56:01 -0700] "GET /images/logo.png HTTP/1.1" 200 4512
127.0.0.1 - - [10/Oct/2023:13:58:12 -0700] "GET /login?data=32233131352d303f7f2b2d2f31 HTTP/1.1" 404 134
127.0.0.1 - - [10/Oct/2023:13:59:05 -0700] "GET /about.html HTTP/1.1" 200 1024
EOF

    cat << 'EOF' > /home/user/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class BackdoorHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/backdoor_73':
            auth_header = self.headers.get('X-Backdoor-Auth')
            if auth_header == 'ioms':
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"flag": "FLAG{cxx_vuln_sc4nn3r_991}"}).encode())
                return
            else:
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b"Forbidden")
                return
        elif self.path.startswith('/api/backdoor_'):
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not Found")
            return

        self.send_response(404)
        self.end_headers()

if __name__ == '__main__':
    server_address = ('127.0.0.1', 8080)
    httpd = HTTPServer(server_address, BackdoorHandler)
    httpd.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
