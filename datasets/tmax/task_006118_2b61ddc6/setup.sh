#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    mkdir -p /home/user/curated
    mkdir -p /home/user/logs

    cat << 'EOF' > /tmp/make_zips.py
import zipfile
import os

# Zip 1: Has malicious paths
with zipfile.ZipFile('/home/user/incoming/build_v1.zip', 'w') as z:
    z.writestr('safe1.txt', 'safe data')
    z.writestr('dir/safe2.txt', 'more safe data')
    z.writestr('../escape.txt', 'evil data')
    z.writestr('/absolute.txt', 'evil data 2')

# Zip 2: Purely benign
with zipfile.ZipFile('/home/user/incoming/build_v2.zip', 'w') as z:
    z.writestr('config.json', '{"status": "ok"}')
EOF

    python3 /tmp/make_zips.py
    rm /tmp/make_zips.py

    chmod -R 777 /home/user
