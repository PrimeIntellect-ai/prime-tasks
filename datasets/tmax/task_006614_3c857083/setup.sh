#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/backup_data
    cat << 'EOF' > /home/user/backup_data/system.log
2023-10-25 08:12:01 INFO Backup service started
2023-10-25 08:12:05 [ARCHIVE_REQ] /etc/hostname 0x1B
2023-10-25 08:12:06 DEBUG Scanning /var/log
2023-10-25 08:12:06 [ARCHIVE_REQ] /var/log/auth.log 0x1A4F
2023-10-25 08:12:07 WARN Skipping unreadable file /etc/shadow
2023-10-25 08:12:08 [ARCHIVE_REQ] /home/user/.bashrc 0xE74
2023-10-25 08:12:10 INFO Backup service sleeping
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
