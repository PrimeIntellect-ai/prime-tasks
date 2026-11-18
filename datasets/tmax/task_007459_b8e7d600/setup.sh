#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc gzip tar
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data/raw_logs
mkdir -p /home/user/data/processed_logs

cat << 'EOF' > /home/user/data/processed_logs/old_log.log
BEGIN_RECORD
ID: 10
LEVEL: CRITICAL
MESSAGE: System boot failure
END_RECORD
EOF

cd /home/user/data
tar -cg /home/user/data/snapshot.snar -f /home/user/data/base_backup.tar processed_logs/

cat << 'EOF' > /home/user/data/raw_logs/log1.raw
BEGIN_RECORD
ID: 101
LEVEL: INFO
MESSAGE: Everything is fine
END_RECORD
BEGIN_RECORD
ID: 102
LEVEL: ERROR
MESSAGE: Disk space low
END_RECORD
BEGIN_RECORD
ID: 103
LEVEL: DEBUG
MESSAGE: Variable x=5
END_RECORD
EOF
gzip -c /home/user/data/raw_logs/log1.raw > /home/user/data/raw_logs/log1.gz
rm /home/user/data/raw_logs/log1.raw

cat << 'EOF' > /home/user/data/raw_logs/log2.raw
BEGIN_RECORD
ID: 201
LEVEL: CRITICAL
MESSAGE: Kernel panic
END_RECORD
BEGIN_RECORD
ID: 202
LEVEL: WARNING
MESSAGE: High memory usage
END_RECORD
EOF
gzip -c /home/user/data/raw_logs/log2.raw > /home/user/data/raw_logs/log2.gz
rm /home/user/data/raw_logs/log2.raw

chmod -R 777 /home/user
