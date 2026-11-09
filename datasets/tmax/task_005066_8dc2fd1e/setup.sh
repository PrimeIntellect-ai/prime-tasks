#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/legacy_configs
    mkdir -p /home/user/backup

    cat << 'EOF' > /tmp/setup.py
import os
os.makedirs('/home/user/legacy_configs', exist_ok=True)
os.makedirs('/home/user/backup', exist_ok=True)

files = {
    'cache.ini': '[Cache]\nbackend=redis\nttl=3600\n',
    'db.ini': '[Database]\nhost=127.0.0.1\nport=5432\n',
    'web.ini': '[Web]\ndomain=example.com\nworkers=4\n'
}

for name, content in files.items():
    with open(f'/home/user/legacy_configs/{name}', 'wb') as f:
        f.write(content.encode('utf-16le'))
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
