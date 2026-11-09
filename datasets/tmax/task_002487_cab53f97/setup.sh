#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    mkdir -p /home/user/certs
    mkdir -p /home/user/logs
    mkdir -p /home/user/uploads

    cat << 'EOF' > /home/user/logs/app.log
2023-10-01 10:00:01 INFO Server started
2023-10-01 10:05:22 DEBUG Received payload API_KEY=v1_secret_9982_abcd
2023-10-01 10:06:00 ERROR Upload failed
2023-10-01 10:10:15 DEBUG Retry upload API_KEY=v1_secret_9982_abcd
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod 644 /home/user/logs/app.log
