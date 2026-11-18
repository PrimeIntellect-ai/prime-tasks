#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip logrotate coreutils bash systemd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.config/systemd/user/
    cat << 'EOF' > /home/user/.config/systemd/user/storage-monitor.service
[Unit]
Description=User Storage Monitor

[Service]
ExecStart=/home/user/monitor.sh
Type=oneshot
EOF

    cat << 'EOF' > /home/user/mock_fstab
UUID=xxxx / ext4 defaults 1 1
UUID=yyyy /home ext4 defaults 1 2
UUID=zzzz /nonexistent_mnt ext4 defaults 1 2
EOF
    chmod 644 /home/user/mock_fstab

    chmod -R 777 /home/user
