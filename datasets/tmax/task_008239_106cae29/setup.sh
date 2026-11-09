#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/rules.conf
MAX_DAYS=30
TARGET_LEVEL=CRITICAL
ARCHIVE_FILE=/home/user/critical_archive.log
EOF

    cat << 'EOF' > /home/user/system.log
[2023-10-25 14:00:00] INFO Starting backup job.
[2023-10-25 14:05:00] CRITICAL Disk space exhausted:
Volume /dev/sda1 has 0 bytes left.
Please free up space immediately.
[2023-10-25 14:06:00] WARN Cleanup script failed.
[2023-10-25 14:10:00] CRITICAL Database connection lost:
Error 104: Connection reset by peer
Stack trace:
  at db_connect()
  at main()
[2023-10-25 14:15:00] INFO Retrying connection...
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
