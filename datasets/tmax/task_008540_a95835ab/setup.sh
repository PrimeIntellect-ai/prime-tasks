#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git curl
    pip3 install pytest

    # Set global git configurations to facilitate agent commits
    git config --global user.email "agent@example.com"
    git config --global user.name "Agent"
    git config --global init.defaultBranch main

    # Create bare repo
    mkdir -p /home/user/app.git
    git init --bare --initial-branch=main /home/user/app.git

    # Create deploy dir
    mkdir -p /home/user/deploy

    # Create workspace
    mkdir -p /home/user/workspace
    cd /home/user/workspace
    git init --initial-branch=main
    git remote add origin /home/user/app.git

    # Create dummy python server
    cat << 'EOF' > /home/user/workspace/server.py
import http.server
import socketserver

PORT = 8080
Handler = http.server.SimpleHTTPRequestHandler
with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
