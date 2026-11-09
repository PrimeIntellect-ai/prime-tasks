#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip xxd
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/app.log
[INFO] Application started
[DEBUG] Checking token: DEADc0ffee123456
[INFO] User authenticated successfully
[ERROR] Failed to validate backup token DEADc0ffee123456 - timeout
[INFO] Shutting down
EOF

    cat << 'EOF' > /home/user/config.ini
[Server]
Port=8080
Host=127.0.0.1

[Authentication]
API_KEY=DEADc0ffee123456
Timeout=30
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
