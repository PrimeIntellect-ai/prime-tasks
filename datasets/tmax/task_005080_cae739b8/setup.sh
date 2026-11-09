#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/backup_data /home/user/logs
    cat << 'EOF' > /home/user/backup_data/fstab.mock
# Mock fstab for restore testing
/dev/sda1 / ext4 defaults 1 1
/dev/sda2 /boot ext2 defaults 1 2
/dev/sdb1 /var/www ext4 ro,noatime 0 0
/dev/sdb2 /data/db xfs defaults 0 0
/dev/sdc1 /opt/app/backup ext4 rw,nosuid 0 2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
