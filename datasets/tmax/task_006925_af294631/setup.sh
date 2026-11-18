#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip qemu-system-x86
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/service_configs
    mkdir -p /home/user/system_data

    cat << 'EOF' > /home/user/system_data/monitor.json
{
    "host": "127.0.0.1",
    "port": 5902
}
EOF

    ln -s /home/user/nonexistent_legacy/monitor.json /home/user/service_configs/monitor.json

    cat << 'EOF' > /home/user/monitor.py
import time
import socket
import json
import os
import sys

CONFIG_PATH = "/home/user/service_configs/monitor.json"

if not os.path.exists(CONFIG_PATH):
    print("Config missing")
    sys.exit(1)

with open(CONFIG_PATH, "r") as f:
    config = json.load(f)

host = config.get("host", "127.0.0.1")
port = config.get("port", 5902)

while True:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(2)
            s.connect((host, port))
            # VNC server sends a protocol version string upon connection
            data = s.recv(12)
            if b"RFB" in data:
                with open("/home/user/uptime.log", "a") as log:
                    log.write("VNC_OK\n")
            else:
                with open("/home/user/uptime.log", "a") as log:
                    log.write("VNC_FAIL\n")
    except Exception as e:
        pass
    time.sleep(1)
EOF
    chmod +x /home/user/monitor.py

    chmod -R 777 /home/user
