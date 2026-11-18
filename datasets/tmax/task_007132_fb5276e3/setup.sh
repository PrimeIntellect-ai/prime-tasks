#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/input
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/input/retries.tsv
2023-10-01T10:00:00Z	Hello 🌍
2023-10-01T10:01:00Z	Привет 🌍
2023-10-01T10:02:00Z	Hello 🌍
2023-10-01T10:03:00Z	مرحبا
2023-10-01T10:04:00Z	مرحبا بك
2023-10-01T10:05:00Z	Hello 🌍
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
