#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user/config_data/sub
echo "app_mode=test" > /home/user/config_data/app.ini
echo "db_port=5432" > /home/user/config_data/sub/db.conf
ln -s /home/user/config_data /home/user/config_data/sub/loop

cat << 'EOF' > /home/user/backup.conf
TARGET=/home/user/config_data
OUTPUT=/home/user/manifest.txt
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
