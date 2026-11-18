#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/archive_config.txt
# Master Backup Config
MAX_THREADS = 4
ARCHIVE_DEST = /home/user/secure_vault/archive_2024   # Target for sanitized logs
RETENTION_DAYS = 365
EOF

    cat << 'EOF' > /home/user/raw_backup.log
[KEEP] System boot initiated at 04:00.
[DISCARD] Debug: variable x initialized to 0.
[KEEP] user admin logged in from 192.168.1.50.
[KEEP] database backup completed successfully.
[DISCARD] Cache miss on query #4928.
[KEEP] warning: disk space on /dev/sda1 is at 85%.
[DISCARD] Health check ping received.
[DISCARD] Health check ping received.
[KEEP] error: failed to write to sector 7A.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
