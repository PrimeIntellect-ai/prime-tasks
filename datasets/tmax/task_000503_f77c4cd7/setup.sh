#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    mkdir -p /home/user/app/archive
    cat << 'EOF' > /home/user/app/data.log
INFO: Application started
ERROR: Connection timeout on port 8080
DEBUG: Memory usage at 45%
ERROR: Disk space low on /dev/sda1
INFO: Shutting down
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod 644 /home/user/app/data.log
