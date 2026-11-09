#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/mounts/app_data
    mkdir -p /home/user/mounts/backup

    cat << 'EOF' > /home/user/dashboard_fstab.conf
# Custom fstab for dashboard metrics
/dev/sda1 /home/user/mounts/app_data ext4 defaults 0 0
/dev/sdb1 /home/user/mounts/backup ext4 defaults 0 0
/dev/sdc1 /home/user/mounts/offline ext4 defaults 0 0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
