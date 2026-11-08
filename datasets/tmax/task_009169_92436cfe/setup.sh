#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/analyzer.py
import sys
import os
import time

socket_path = "/home/user/planner/run/socket"
if not os.path.exists(socket_path):
    print(f"Error: {socket_path} does not exist.")
    sys.exit(1)

if not os.path.islink(socket_path):
    print(f"Error: {socket_path} is not a symlink.")
    sys.exit(1)

target = os.readlink(socket_path)
if target != "/home/user/app/metrics.sock":
    print(f"Error: Symlink points to {target}, expected /home/user/app/metrics.sock")
    sys.exit(1)

print("Analyzer started successfully. Processing metrics...")
# Simulate some work then crash to test the restart and log rotation
time.sleep(0.5)
print("Fatal: Simulated OOM exception.")
sys.exit(1)
EOF

    chmod -R 777 /home/user
