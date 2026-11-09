#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx haproxy curl
    pip3 install --default-timeout=100 pytest requests

    mkdir -p /home/user/data/node1
    mkdir -p /home/user/data/node2
    mkdir -p /home/user/data/node3

    mkdir -p /app
    cat << 'EOF' > /app/traffic_gen
#!/usr/bin/env python3
import sys
import time
import json
import requests
import random
import argparse
import os

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target', required=True)
    args = parser.parse_args()

    successes = 0
    total = 0
    start_time = time.time()

    # Run for a few seconds to simulate traffic
    while time.time() - start_time < 5:
        total += 1
        try:
            payload = b"0" * (1024 * 1024) # 1MB
            res = requests.post(f"{args.target}/upload", data=payload, timeout=2)
            if res.status_code == 200:
                successes += 1
        except Exception:
            pass
        time.sleep(0.1)

    # Check directories
    dirs = ["/home/user/data/node1", "/home/user/data/node2", "/home/user/data/node3"]
    violation = False
    for d in dirs:
        size = 0
        if os.path.exists(d):
            for f in os.listdir(d):
                size += os.path.getsize(os.path.join(d, f))
        if size > 50 * 1024 * 1024:
            violation = True

    rate = (successes / total) if total > 0 else 0
    if violation:
        rate = 0.0

    print(json.dumps({"success_rate": rate}))

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/traffic_gen

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
