#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server openssh-client cargo
    pip3 install pytest

    mkdir -p /run/sshd

    mkdir -p /home/user/monitor_src/src
    mkdir -p /home/user/deploy/staging
    mkdir -p /home/user/deploy/production
    mkdir -p /home/user/mail_spool
    mkdir -p /home/user/.ssh

    ssh-keygen -t ed25519 -f /home/user/.ssh/id_ed25519 -N ""
    cat /home/user/.ssh/id_ed25519.pub >> /home/user/.ssh/authorized_keys
    chmod 600 /home/user/.ssh/authorized_keys
    ssh-keyscan localhost >> /home/user/.ssh/known_hosts

    cat << 'EOF' > /home/user/monitor_src/Cargo.toml
[package]
name = "monitor"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1", features = ["full"] }
reqwest = { version = "0.11", features = ["json"] }
lettre = { version = "0.10", features = ["builder", "file-transport"] }
EOF

    cat << 'EOF' > /home/user/dummy_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
class HealthCheckHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")
server = HTTPServer(('127.0.0.1', 9090), HealthCheckHandler)
server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
