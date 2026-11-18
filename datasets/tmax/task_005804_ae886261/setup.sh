#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/manifest.conf
# Configuration Manifest
# Last updated: today

MAX_CONNECTIONS = 100
  ACTIVE_CONFIG_PATH   =  /home/user/live_config.bin 
TIMEOUT=30
EOF

    cat << 'EOF' > /home/user/writer.py
import time
import fcntl
import os

path = '/home/user/live_config.bin'
with open(path, 'wb') as f:
    f.write(b'INIT_DATA\n')

while True:
    with open(path, 'r+b') as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.seek(0)
        f.write(b'DATA_' + os.urandom(10) + b'\n')
        time.sleep(0.1)
        fcntl.flock(f, fcntl.LOCK_UN)
    time.sleep(0.1)
EOF

    # Initialize live_config.bin
    echo -n "INIT_DATA" > /home/user/live_config.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
