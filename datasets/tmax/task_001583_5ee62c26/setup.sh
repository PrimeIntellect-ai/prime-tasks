#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip zip tar coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/legacy_backups/2021/q1
mkdir -p /home/user/legacy_backups/2021/q2/misc
mkdir -p /home/user/legacy_backups/2022/staging

# Create valid zip
echo "Data 1" > /tmp/data1.txt
zip -j /home/user/legacy_backups/2021/q1/data_backup_v1.zip /tmp/data1.txt

# Create valid tar.gz
echo "Data 2" > /tmp/data2.txt
tar -czf /home/user/legacy_backups/2021/q2/misc/logs_final.tar.gz -C /tmp data2.txt

# Create another valid zip
echo "Data 3" > /tmp/data3.txt
zip -j /home/user/legacy_backups/2022/staging/db_dump_old.zip /tmp/data3.txt

# Create corrupt zip (valid header, truncated)
head -c 50 /home/user/legacy_backups/2021/q1/data_backup_v1.zip > /home/user/legacy_backups/2021/q2/misc/broken_archive.zip

# Create corrupt tar.gz (random garbage)
head -c 100 /dev/urandom > /home/user/legacy_backups/2022/staging/incomplete_transfer.tar.gz

# Cleanup tmp
rm /tmp/data1.txt /tmp/data2.txt /tmp/data3.txt

chown -R user:user /home/user/legacy_backups
chmod -R 777 /home/user
