#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/app_dirty.log
INFO: [2023-10-12 08:23:45] Client connected from 192.168.1.100. Auth successful for alice@example.com.
DEBUG: Connection timeout for 10.0.0.5. No user associated.
ERROR: [2023-10-12 08:25:01] Failed login attempt from 172.16.254.1 for user bob.smith@domain.co.uk - invalid password.
WARN: User charlie@company.com disconnected unexpectedly. Time: 2023-10-12 08:30:00. IP: 8.8.8.8.
INFO: [2023-10-12 09:00:15] Server health check passed.
INFO: [2023-10-12 09:05:22] - 127.0.0.1 - admin@localhost started maintenance.
EOF
    chmod 644 /home/user/app_dirty.log

    chmod -R 777 /home/user
