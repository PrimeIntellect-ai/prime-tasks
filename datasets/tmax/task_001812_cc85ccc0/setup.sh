#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    cat << 'EOF' > /home/user/app/ingest.py
#!/usr/bin/env python3
import os
import json
import time

def run_service():
    # 1. Check symlink structure
    data_dir = '/home/user/app/data'
    if not os.path.islink(data_dir):
        print("CRITICAL: Data directory is not a symlink")
        exit(1)
    if os.readlink(data_dir) != '/home/user/data_mount/active':
        print("CRITICAL: Data directory symlink destination incorrect")
        exit(1)

    # 2. Check Timezone
    if os.environ.get('TZ') != 'UTC':
        print("CRITICAL: Service must run with TZ=UTC")
        exit(1)

    # 3. Check container lifecycle config
    try:
        with open('/home/user/config/containers.json', 'r') as f:
            config = json.load(f)
            if config.get('ingest-worker', {}).get('status') != 'running':
                print("CRITICAL: Container ingest-worker is not running")
                exit(1)
    except FileNotFoundError:
        print("CRITICAL: /home/user/config/containers.json missing")
        exit(1)

    # Success
    with open('/home/user/app/success.log', 'w') as f:
        f.write("SERVICE_STARTED_SUCCESSFULLY")
    print("Service started successfully.")

if __name__ == '__main__':
    run_service()
EOF
    chmod +x /home/user/app/ingest.py

    chmod -R 777 /home/user
