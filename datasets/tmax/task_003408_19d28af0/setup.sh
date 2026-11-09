#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/.config/systemd/user/
cat << 'EOF' > /home/user/.config/systemd/user/data-analyzer.service
[Unit]
Description=Data Analyzer Service

[Service]
ExecStart=/usr/bin/python3 -m http.server 8080
Restart=always

[Install]
WantedBy=default.target
EOF

mkdir -p /home/user/deploy/releases/v1
mkdir -p /home/user/deploy/releases/v2
ln -s /home/user/deploy/releases/v2 /home/user/deploy/current

chmod -R 777 /home/user
