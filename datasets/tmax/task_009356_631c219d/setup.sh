#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_data/sub1
    mkdir -p /home/user/app_data/sub2

    cat << 'EOF' > /home/user/vulnerability_scan.txt
INFO: Scan started
CRITICAL: Unauthorized listener on TCP port 8080
WARN: High memory usage
CRITICAL: Unauthorized listener on TCP port 31337
INFO: Checking files
CRITICAL: Unauthorized listener on TCP port 4444
CRITICAL: Unauthorized listener on TCP port 8080
EOF

    echo "ALLOW_ANON=true" > /home/user/app_data/sub1/server.conf
    echo "ALLOW_AUTH=true" > /home/user/app_data/sub1/secure.conf
    echo "User config ALLOW_ANON enabled" > /home/user/app_data/sub2/api.conf
    echo "ALLOW_ANON=false" > /home/user/app_data/safe.txt

    touch /home/user/.bashrc

    chmod -R 777 /home/user
