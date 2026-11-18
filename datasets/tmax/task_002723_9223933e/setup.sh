#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang espeak systemd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/oracle
    mkdir -p /home/user/.config/systemd/user
    mkdir -p /home/user/src
    mkdir -p /home/user/bin

    espeak -w /app/migration_memo.wav "The new backup destination is operation thunderbird."

    cat << 'EOF' > /home/user/.config/systemd/user/ssh-tunnel.service
[Unit]
Description=SSH Tunnel

[Service]
ExecStart=/bin/sleep 3600
EOF

    cat << 'EOF' > /home/user/.config/systemd/user/storage-sync.service
[Unit]
Description=Storage Sync Service

[Service]
ExecStart=/bin/sleep 3600

[Install]
WantedBy=default.target
EOF

    cat << 'EOF' > /app/oracle/path_sanitizer
#!/usr/bin/env python3
import sys, re
input_str = sys.stdin.read().strip()
input_str = input_str.lower()
input_str = input_str.replace(' ', '-')
input_str = re.sub(r'[^a-z0-9\-_/.]', '', input_str)
input_str = re.sub(r'/+', '/', input_str)
if not input_str.startswith('/'):
    input_str = '/' + input_str
sys.stdout.write(f"/storage/backups/operation_thunderbird{input_str}")
EOF

    chmod +x /app/oracle/path_sanitizer

    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
