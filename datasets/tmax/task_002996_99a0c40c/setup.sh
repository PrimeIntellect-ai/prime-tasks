#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/observability

    cat << 'EOF' > /home/user/observability/config.ini
[backend]
target_port = 8888

[storage]
mount_device = /dev/mapper/data-vol
EOF

    cat << 'EOF' > /home/user/observability/fstab.mock
/dev/mapper/os-vol / ext4 defaults 1 1
/dev/mapper/data-vol /home/user/test_mnt ext4 defaults,noatime 0 2
EOF

    chown -R user:user /home/user/observability
    chmod -R 777 /home/user
