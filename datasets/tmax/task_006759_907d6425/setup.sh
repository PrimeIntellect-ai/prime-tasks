#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc tar gzip
pip3 install pytest

mkdir -p /home/user/logs
cat << 'EOF' > /home/user/logs/backup_1.log
BEGIN_JOB
JobID: 101
Status: SUCCESS
Files: 50
END_JOB
BEGIN_JOB
JobID: 102
Status: FAILED
Files: 12
END_JOB
BEGIN_JOB
JobID: 103
Status: FAILED
Files: 5
END_JOB
EOF

cat << 'EOF' > /home/user/logs/backup_2.log
BEGIN_JOB
JobID: 201
Status: FAILED
Files: 100
END_JOB
BEGIN_JOB
JobID: 202
Status: SUCCESS
Files: 10
END_JOB
BEGIN_JOB
JobID: 203
Status: FAILED
Files: 8
END_JOB
EOF

cd /home/user
tar -czf backups.tar.gz logs/backup_1.log logs/backup_2.log
rm -rf /home/user/logs

cat << 'EOF' > /home/user/filter.conf
TARGET_STATUS=FAILED
MIN_FILES=10
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
