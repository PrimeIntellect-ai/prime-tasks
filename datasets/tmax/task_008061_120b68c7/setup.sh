#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_logs/

    cat << 'EOF' > /home/user/app_logs/log1.txt
[INFO] Application started
[INFO] Application started
[DEBUG] Loading modules...
[DEBUG] Loading modules...
[WARN] High memory usage
[WARN] High memory usage
[WARN] High memory usage
EOF

    cat << 'EOF' > /home/user/app_logs/log2.txt
[INFO] User login
[INFO] User login
[DEBUG] DB query executed
[ERROR] Connection timeout
[ERROR] Connection timeout
EOF

    cat << 'EOF' > /home/user/app_logs/log3.txt
[DEBUG] Heartbeat sent
[DEBUG] Heartbeat sent
[INFO] Job finished
[INFO] Job finished
[INFO] Job finished
EOF

    chmod -R 777 /home/user
