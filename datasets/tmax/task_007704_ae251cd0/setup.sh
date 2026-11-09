#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/real_logs
    mkdir -p /home/user/real_data
    mkdir -p /home/user/real_backups
    mkdir -p /home/user/mnt

    # Create dummy files
    dd if=/dev/zero of=/home/user/real_logs/app.log bs=1M count=12 2>/dev/null
    dd if=/dev/zero of=/home/user/real_data/db.sqlite bs=1M count=30 2>/dev/null
    dd if=/dev/zero of=/home/user/real_backups/archive.tar.gz bs=1M count=25 2>/dev/null

    # Create symlinks
    ln -s /home/user/real_logs /home/user/mnt/logs
    ln -s /home/user/real_data /home/user/mnt/data
    ln -s /home/user/real_backups /home/user/mnt/backups

    # Create storage_fstab
    cat <<EOF > /home/user/storage_fstab
/home/user/mnt/logs 10
/home/user/mnt/data 50
/home/user/mnt/backups 20
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
