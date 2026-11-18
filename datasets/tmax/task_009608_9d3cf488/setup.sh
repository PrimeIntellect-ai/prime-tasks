#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/app
    mkdir -p /home/user/data/backups

    cat << 'EOF' > /home/user/fstab_config
# Custom application mounts
/dev/sda1 /home/user/data/app ext4 defaults 0 0
/dev/sdb1 /home/user/data/backups ext4 defaults 0 0
/dev/sdc1 /home/user/data/missing ext4 defaults 0 0
EOF

    cat << 'EOF' > /home/user/quota_config.json
{
  "/home/user/data/app": 5000,
  "/home/user/data/backups": 10000,
  "/home/user/data/missing": 2000
}
EOF

    dd if=/dev/zero of=/home/user/data/app/file1.txt bs=3000 count=1 2>/dev/null
    dd if=/dev/zero of=/home/user/data/app/file2.txt bs=3000 count=1 2>/dev/null
    chmod 644 /home/user/data/app/file1.txt
    chmod 644 /home/user/data/app/file2.txt

    dd if=/dev/zero of=/home/user/data/backups/backup1.tar.gz bs=8000 count=1 2>/dev/null
    chmod 777 /home/user/data/backups/backup1.tar.gz

    chmod -R 777 /home/user
