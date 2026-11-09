#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/mock_etc
    mkdir -p /home/user/app_backup

    cat << 'EOF' > /home/user/mock_etc/fstab
# /etc/fstab: static file system information.
UUID=1234-5678 / ext4 errors=remount-ro 0 1
EOF

    cat << 'EOF' > /home/user/mock_etc/firewall.rules
# Custom firewall rules
ALLOW TCP 22
ALLOW TCP 80
EOF

    chmod -R 777 /home/user
