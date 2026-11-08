#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/migration

    cat << 'EOF' > /home/user/migration/fstab_mock
/home/user/data_vol1 ext4 8081
/home/user/data_vol2 xfs 8082
EOF

    chmod -R 777 /home/user
