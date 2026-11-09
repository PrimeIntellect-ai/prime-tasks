#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/raw_logs

cat << 'EOF' > /home/user/archive_rules.conf
[Backup]
source_dir = /home/user/raw_logs
error_filter = CRITICAL
output_file = /home/user/filtered_logs.json
archive_name = /home/user/critical_backup.tar.gz
EOF

cat << 'EOF' > /home/user/raw_logs/app1.log
[2023-10-15 08:30:12] INFO
Application started successfully.
Connecting to database.
===
[2023-10-15 08:35:00] CRITICAL
Database connection timeout.
Retries exhausted.
Check the network partition.
===
[2023-10-15 08:40:00] ERROR
Failed to parse user input.
===
EOF

cat << 'EOF' > /home/user/raw_logs/app2.log
[2023-10-16 11:20:00] WARNING
Disk space running low.
===
[2023-10-16 11:25:05] CRITICAL
Out of memory exception.
Process killed by OOM killer.
===
EOF

chmod -R 777 /home/user
