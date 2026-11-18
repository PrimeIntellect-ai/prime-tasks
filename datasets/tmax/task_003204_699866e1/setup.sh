#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/mock_fstab
# /etc/fstab: static file system information.
LABEL=cloudimg-rootfs   /        ext4   defaults        0 1
10.0.0.5:/storage       /mnt/nfs_backup  nfs4   ro,hard,intr    0 0
tmpfs                   /run     tmpfs  rw,nosuid,nodev 0 0
EOF

    chmod -R 777 /home/user
