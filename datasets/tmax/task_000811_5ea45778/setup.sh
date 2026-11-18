#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar coreutils openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_data_source
    cat << 'EOF' > /home/user/app_data_source/app.py
import os

def connect():
    SECRET_TOKEN = "legacy_token_A1B2C3"
    print(f"Connecting with {SECRET_TOKEN}")
EOF

    cat << 'EOF' > /home/user/app_data_source/allowed_ips.txt
192.168.1.50
10.0.0.15
172.16.20.5
EOF

    cd /home/user/app_data_source
    tar -czf /home/user/archive.tar.gz app.py allowed_ips.txt
    cd /home/user
    base64 /home/user/archive.tar.gz > /home/user/incoming_data.b64
    rm -rf /home/user/app_data_source /home/user/archive.tar.gz

    chmod -R 777 /home/user
