#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/app/worker.py
#!/usr/bin/env python3
import os
import time
import sys

data_dir = os.environ.get("DATA_DIR", "./wrong_data_dir")
if not os.path.exists(data_dir):
    try:
        os.makedirs(data_dir)
    except:
        pass

log_file = os.path.join(data_dir, "worker.log")

while True:
    try:
        with open(log_file, "a") as f:
            f.write(f"{time.time()}: Worker heartbeat\n")
            f.flush()
    except Exception as e:
        print(f"Error writing to {log_file}: {e}")
    time.sleep(5)
EOF
    chmod +x /home/user/app/worker.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
