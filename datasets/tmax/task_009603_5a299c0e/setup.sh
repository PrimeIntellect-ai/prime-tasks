#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo curl
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/raw.txt
Hello World
Data Engineering 101
Rust 2024!
AI Agents are cool
1234567890
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
