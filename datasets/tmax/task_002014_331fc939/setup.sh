#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/legacy_service
echo "legacy data" > /home/user/legacy_service/data.txt
mkdir -p /home/user/archive
mkdir -p /home/user/cloud_service
mkdir -p /home/user/services

cat << 'EOF' > /home/user/services/cloud-worker.service
[Unit]
Description=Cloud Worker Service
ConditionPathExists=/home/user/cloud_service

[Service]
ExecStart=/usr/bin/python3 /home/user/cloud_service/worker.py
Restart=always

[Install]
WantedBy=default.target
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
