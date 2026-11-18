#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc build-essential tar gzip
pip3 install pytest

mkdir -p /home/user/source_data /home/user/backup_dir /home/user/staging_dir
echo "file1_content" > /home/user/source_data/file1.txt
echo "file2_content" > /home/user/source_data/file2.txt

cat << 'EOF' > /home/user/migration.conf
SOURCE_DIR=/home/user/source_data
BACKUP_DIR=/home/user/backup_dir
STAGE_DIR=/home/user/staging_dir
CHECK_PORT=8123
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
