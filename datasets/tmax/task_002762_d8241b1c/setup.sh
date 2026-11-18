#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip systemd openssh-server openssh-client espeak-ng curl
    pip3 install pytest flask grpcio

    useradd -m -s /bin/bash user || true

    mkdir -p /app
    espeak-ng -w /app/voicemail.wav "Authorization code delta seven nine omega."

    mkdir -p /home/user/.config/systemd/user
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/.config/systemd/user/voicemail-api.service
[Unit]
Description=Voicemail API Service

[Service]
Type=simple
WorkingDirectory=/home/user/app
ExecStart=/usr/bin/python3 /home/user/app/server.py

[Install]
WantedBy=default.target
EOF

    cat << 'EOF' > /home/user/app/server.py
import os
import sys
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading
import socket

if os.environ.get('TZ') != 'Europe/Zurich' or os.environ.get('LANG') != 'fr_CH.UTF-8':
    print("Crash: Invalid TZ or LANG")
    sys.exit(1)

TRANSCRIPT_TEXT = ""

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/transcript':
            auth = self.headers.get('Authorization')
            if auth != 'Bearer voicemail-admin':
                self.send_response(401)
                self.end_headers()
                return
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            data = {
                "transcript": TRANSCRIPT_TEXT,
                "tz": os.environ.get('TZ'),
                "locale": os.environ.get('LANG')
            }
            self.wfile.write(json.dumps(data).encode())
        else:
            self.send_response(404)
            self.end_headers()

def run_http():
    server = HTTPServer(('127.0.0.1', 8080), Handler)
    server.serve_forever()

def run_grpc_dummy():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('127.0.0.1', 50051))
    s.listen(1)
    while True:
        try:
            conn, addr = s.accept()
            conn.close()
        except:
            pass

if __name__ == '__main__':
    threading.Thread(target=run_http, daemon=True).start()
    run_grpc_dummy()
EOF

    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -f /home/user/.ssh/id_rsa -N ""
    cat /home/user/.ssh/id_rsa.pub >> /home/user/.ssh/authorized_keys
    chmod 700 /home/user/.ssh
    chmod 600 /home/user/.ssh/authorized_keys

    # Ensure sshd can run
    mkdir -p /run/sshd

    chown -R user:user /home/user
    chmod -R 777 /home/user
