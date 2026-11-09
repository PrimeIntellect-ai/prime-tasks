#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest supervisor

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/netmon/config/available
    mkdir -p /home/user/netmon/supervisor/conf.d
    mkdir -p /home/user/netmon/bin
    mkdir -p /home/user/netmon/logs
    mkdir -p /home/user/netmon/run

    cat << 'EOF' > /home/user/netmon/config/available/production.json
{"endpoint": "10.0.0.5", "timeout": 5}
EOF

    ln -s /home/user/netmon/config/available/development.json /home/user/netmon/config/active.json

    cat << 'EOF' > /home/user/netmon/bin/monitor.py
#!/usr/bin/env python3
import json
import time
import sys
import os

config_path = "/home/user/netmon/config/active.json"
log_path = "/home/user/netmon/logs/connectivity.log"

if not os.path.exists(config_path):
    print("Config missing, crashing...")
    sys.exit(1)

with open(config_path, "r") as f:
    config = json.load(f)

if config.get("endpoint") == "10.0.0.5":
    with open(log_path, "a") as f:
        f.write("STATUS: PING_SUCCESS\n")
    # Simulate a network drop crash to test autorestart
    time.sleep(1)
    sys.exit(1)
else:
    sys.exit(1)
EOF
    chmod +x /home/user/netmon/bin/monitor.py

    cat << 'EOF' > /home/user/netmon/supervisor/supervisord.conf
[unix_http_server]
file=/home/user/netmon/run/supervisor.sock

[supervisord]
logfile=/home/user/netmon/logs/supervisord.log
pidfile=/home/user/netmon/run/supervisord.pid
nodaemon=false

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///home/user/netmon/run/supervisor.sock

[include]
files = /home/user/netmon/supervisor/conf.d/*.conf
EOF

    cat << 'EOF' > /home/user/netmon/supervisor/conf.d/netmon.conf
[program:netmon]
command=/home/user/netmon/bin/monitor.py
autorestart=false
stdout_logfile=/home/user/netmon/logs/netmon.out
stderr_logfile=/home/user/netmon/logs/netmon.err
EOF

    chmod -R 777 /home/user
