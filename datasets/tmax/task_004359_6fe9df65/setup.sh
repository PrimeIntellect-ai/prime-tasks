#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential wget cron
    pip3 install pytest pandas numpy

    # 1. Vendor cJSON
    mkdir -p /app
    cd /app
    wget https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.15.tar.gz
    tar -xzf v1.7.15.tar.gz
    rm v1.7.15.tar.gz
    # Apply perturbation
    sed -i 's/-fPIC//g' /app/cJSON-1.7.15/Makefile

    # Create user
    useradd -m -s /bin/bash user || true

    # 2. Generate sample data for agent
    cat << 'EOF' > /home/user/config_logs.jsonl
{"timestamp": 1690000000, "file": "/etc/nginx/nginx.conf", "size": 4096}
{"timestamp": 1690000010, "file": "/etc/hosts", "size": 256}
{"timestamp": 1690000020, "file": "/etc/passwd", "size": 2048}
{"timestamp": 1690000030, "file": "/etc/ssh/sshd_config", "size": 3100}
EOF

    # 3. Generate hidden test data for verifier
    cat << 'EOF' > /tmp/hidden_test.jsonl
{"timestamp": 1, "file": "f1", "size": 100}
{"timestamp": 2, "file": "f2", "size": 110}
{"timestamp": 3, "file": "f3", "size": 105}
{"timestamp": 4, "file": "f4", "size": 150}
{"timestamp": 5, "file": "f5", "size": 90}
{"timestamp": 6, "file": "f6", "size": 95}
{"timestamp": 7, "file": "f7", "size": 100}
{"timestamp": 8, "file": "f8", "size": 102}
{"timestamp": 9, "file": "f9", "size": 108}
{"timestamp": 10, "file": "f10", "size": 110}
{"timestamp": 11, "file": "f11", "size": 200}
{"timestamp": 12, "file": "f12", "size": 250}
EOF

    # Ensure permissions
    chown user:user /home/user/config_logs.jsonl
    chmod -R 777 /home/user
    chmod 777 /tmp/hidden_test.jsonl
