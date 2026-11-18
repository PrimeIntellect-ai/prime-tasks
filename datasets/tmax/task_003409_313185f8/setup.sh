#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip supervisor expect
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/service
mkdir -p /home/user/supervisor

cat << 'EOF' > /home/user/service/netmon.py
import sys
import os
import time

CONF_DIR = "/home/user/service/conf"
LOG_DIR = "/home/user/service/logs"
CONF_FILE = os.path.join(CONF_DIR, "settings.json")
LOG_FILE = os.path.join(LOG_DIR, "status.log")

if len(sys.argv) < 2:
    print("Usage: netmon.py [--setup | --serve]")
    sys.exit(1)

if sys.argv[1] == "--setup":
    if not os.path.exists(CONF_DIR):
        print("Error: conf directory missing.")
        sys.exit(1)

    user = input("Enter admin user: ")
    group = input("Enter admin group: ")
    pin = input("Enter initialization PIN: ")

    if pin == "8821":
        with open(CONF_FILE, "w") as f:
            f.write('{"user": "' + user + '", "group": "' + group + '", "configured": true}')
        print("Setup complete.")
        sys.exit(0)
    else:
        print("Invalid PIN.")
        sys.exit(1)

elif sys.argv[1] == "--serve":
    if not os.path.exists(CONF_FILE):
        print("Error: Not configured. Run --setup first.")
        sys.exit(1)
    if not os.path.exists(LOG_DIR):
        print("Error: logs directory missing.")
        sys.exit(1)

    with open(LOG_FILE, "w") as f:
        f.write("SERVICE_ONLINE\n")

    # keep alive
    while True:
        time.sleep(10)
EOF
chmod +x /home/user/service/netmon.py

cat << 'EOF' > /home/user/supervisor/supervisord.conf
[supervisord]
logfile=/home/user/supervisor/supervisord.log
pidfile=/home/user/supervisor/supervisord.pid
nodaemon=false

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[unix_http_server]
file=/home/user/supervisor/supervisor.sock

[supervisorctl]
serverurl=unix:///home/user/supervisor/supervisor.sock

[program:netmon]
command=
autostart=true
autorestart=true
EOF

chmod -R 777 /home/user
