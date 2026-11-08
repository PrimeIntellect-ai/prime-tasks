#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils
pip3 install pytest

mkdir -p /home/user/project_rescue/logs
mkdir -p /home/user/project_rescue/archives
mkdir -p /home/user/project_rescue/config
mkdir -p /home/user/project_rescue/src/subdir
mkdir -p /home/user/project_rescue/src/assets

ln -s /home/user/project_rescue/src/assets /home/user/project_rescue/src/assets/loop_dir
ln -s /home/user/project_rescue/src/ /home/user/project_rescue/src/subdir/root_link

cat << 'EOF' > /home/user/project_rescue/logs/runaway_backup.log
[INFO] 2023-10-01 10:00:00
Operation: Backup
Status: Started
Target: /home/user/project_rescue/src

[ERROR] 2023-10-01 10:00:05
Operation: Backup
Error: Symlink loop detected
Path: /home/user/project_rescue/src/assets/loop_dir
Action: Aborted

[INFO] 2023-10-01 10:01:00
Operation: Retry
Status: Started

[ERROR] 2023-10-01 10:01:05
Operation: Backup
Error: Symlink loop detected
Path: /home/user/project_rescue/src/subdir/root_link
Action: Aborted
EOF

echo "valid data" > /tmp/valid.txt
tar -czf /home/user/project_rescue/archives/backup_valid.tar.gz -C /tmp valid.txt
echo "corrupt data" > /tmp/corrupt.txt
tar -czf /home/user/project_rescue/archives/backup_corrupt.tar.gz -C /tmp corrupt.txt
truncate -s 50 /home/user/project_rescue/archives/backup_corrupt.tar.gz

cat << 'EOF' > /home/user/project_rescue/config/settings.yaml
project:
  source_dir: "BAD_PATH_PREFIX_992"
  data_dir: "BAD_PATH_PREFIX_992/data"
  cache: "BAD_PATH_PREFIX_992/cache"
EOF

touch -d "2023-01-01 10:00:00" /home/user/project_rescue/src/old_file.py
touch -d "2023-10-05 10:00:00" /home/user/project_rescue/src/new_file.py
touch -d "2023-10-05 10:05:00" /home/user/project_rescue/src/subdir/new_data.txt

date -d "2023-05-01 10:00:00" +%s > /home/user/project_rescue/last_backup.timestamp

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
