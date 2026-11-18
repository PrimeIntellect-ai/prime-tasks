#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tar gzip gawk coreutils
pip3 install pytest

# Create directories
mkdir -p /home/user/config_archives
mkdir -p /home/user/extracted_logs

# Create valid archive 1 (batch_01)
mkdir -p /tmp/batch_01
cat << 'EOF' > /tmp/batch_01/changelog.txt
[TRANSACTION]
User: svc_deploy_ops
Timestamp: 1690000000
Modified_Files:
 - /etc/nginx/nginx.conf|a1b2c3d4e5f6
 - /etc/systemd/system/myapp.service|999988887777
!! DEBUG: Flushed routing table cache
[END]
[TRANSACTION]
User: manual_admin
Timestamp: 1690000050
Modified_Files:
 - /etc/sudoers|deadbeef1234
[END]
!! DEBUG: Checking sync status...
EOF
tar -czf /home/user/config_archives/batch_01.tar.gz -C /tmp/batch_01 changelog.txt

# Create valid archive 2 (batch_02)
mkdir -p /tmp/batch_02
cat << 'EOF' > /tmp/batch_02/changelog.txt
!! DEBUG: Initialization started
[TRANSACTION]
User: svc_deploy_ops
Timestamp: 1690000100
Modified_Files:
 - /etc/nginx/nginx.conf|f1e2d3c4b5a6
 - /etc/redis/redis.conf|111122223333
[END]
[TRANSACTION]
User: svc_deploy_ops
Timestamp: 1690000200
Modified_Files:
 - /etc/redis/redis.conf|abcdefabcdef
[END]
EOF
tar -czf /home/user/config_archives/batch_02.tar.gz -C /tmp/batch_02 changelog.txt

# Create corrupted archive
dd if=/dev/urandom of=/home/user/config_archives/batch_err_corrupt.tar.gz bs=1024 count=10

# Clean up tmp
rm -rf /tmp/batch_01 /tmp/batch_02

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
