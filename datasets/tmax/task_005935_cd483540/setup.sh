#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/v1.txt
Bugfix: Memory leak in auth module
Feature: Add dark mode
Update: Dependencies
EOF

    cat << 'EOF' > /home/user/v2.txt
Bugfix: Memory leak in auth module
Feature: Add dark mode
Feature: Reverse proxy support
Bugfix: Rate limiter crash
Update: Dependencies
Security: Update OpenSSL
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
