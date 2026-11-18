#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git supervisor
    pip3 install pytest

    git config --global init.defaultBranch main

    mkdir -p /home/user/api.git
    git -C /home/user/api.git init --bare

    mkdir -p /home/user/api_app

    # Set up local clone
    git clone /home/user/api.git /home/user/local_clone
    cd /home/user/local_clone

    # Create app.py
    cat << 'EOF' > app.py
import time
import http.server
import socketserver
import sys

time.sleep(2) # Simulate slow startup
Handler = http.server.SimpleHTTPRequestHandler
with socketserver.TCPServer(("", 8080), Handler) as httpd:
    httpd.serve_forever()
EOF

    # Create initial failing metrics.py
    cat << 'EOF' > metrics.py
import urllib.request
import sys
import time

def check():
    try:
        response = urllib.request.urlopen('http://localhost:8080', timeout=2)
        if response.status == 200:
            print("OK")
            # keep running
            while True:
                time.sleep(10)
    except Exception as e:
        print("Failed to connect", e)
        sys.exit(1)

if __name__ == "__main__":
    check()
EOF

    git config --global user.email "dev@example.com"
    git config --global user.name "Dev"
    git add app.py metrics.py
    git commit -m "Initial commit"
    git push origin main

    # Initial checkout to api_app
    GIT_WORK_TREE=/home/user/api_app git -C /home/user/api.git checkout -f

    # Create supervisord.conf
    cat << 'EOF' > /home/user/supervisord.conf
[supervisord]
logfile=/home/user/supervisord.log
pidfile=/home/user/supervisord.pid
nodaemon=false

[unix_http_server]
file=/home/user/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///home/user/supervisor.sock

[program:webapp]
command=python3 /home/user/api_app/app.py
autostart=true
autorestart=true

[program:metrics]
command=python3 /home/user/api_app/metrics.py
autostart=true
autorestart=false
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
