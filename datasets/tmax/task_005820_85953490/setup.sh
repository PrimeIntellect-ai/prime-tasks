#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/backup_manifest.log
Backup Job ID: 88472-A
Timestamp: 2023-11-04T08:30:00Z
Volume: /dev/sda1
Requires System Service: postgresql-13.service
Checksum: abc123def456
Status: OK
EOF

    cat << 'EOF' > /home/user/workspace/app.service
[Unit]
Description=Restored Data Analytics Application
Documentation=https://internal.wiki/app

[Service]
ExecStart=/usr/bin/python3 /opt/app/main.py
Restart=on-failure
User=appuser

[Install]
WantedBy=multi-user.target
EOF

    chmod -R 777 /home/user
