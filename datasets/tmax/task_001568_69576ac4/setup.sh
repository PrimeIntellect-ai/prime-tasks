#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc
    pip3 install pytest

    # Create the stripped C binary
    mkdir -p /app/bin
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        return 1;
    }
    if (strlen(argv[1]) > 0 && strlen(argv[2]) == 16) {
        return 0;
    }
    return 1;
}
EOF
    gcc -O2 -s /tmp/oracle.c -o /app/bin/auth_oracle
    rm /tmp/oracle.c

    # Create the auth_service git repository
    mkdir -p /home/user/auth_service
    cd /home/user/auth_service
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import subprocess
import os

API_KEY = os.environ.get("API_KEY", "sec_k99x_memory_extracted_7721")

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/verify':
            if self.headers.get('X-API-Key') != API_KEY:
                self.send_response(401)
                self.end_headers()
                return

            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body)
            except:
                self.send_response(400)
                self.end_headers()
                return
            username = data.get("username", "")
            token = data.get("token", "")

            # Buggy line
            cmd = f"/app/bin/auth_oracle {username} {token}"
            process = subprocess.Popen(cmd, shell=True)
            process.communicate()

            if process.returncode == 0:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"OK")
            else:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(b"Internal Server Error")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8888), RequestHandler)
    server.serve_forever()
EOF

    git add server.py
    git commit -m "Initial commit"

    # Add dummy commits to simulate history
    for i in {1..200}; do
        echo "# commit $i" >> server.py
        git commit -am "Commit $i"
    done

    # Create traffic.pcap
    echo -e "dummy pcap data\nPOST /verify HTTP/1.1\r\nHost: 127.0.0.1:8888\r\n\r\n{\"username\": \"Admin User\", \"token\": \"1234567890123456\"}" > /home/user/traffic.pcap

    # Create crash.core
    echo -e "\x7FELF... dummy core dump ... sec_k99x_memory_extracted_7721 ... more binary data" > /home/user/crash.core

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
