#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl tzdata curl
    pip3 install pytest requests pytz

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/fstab_mock
# /etc/fstab: static file system information.
UUID=9999-9999 / ext4 errors=remount-ro 0 1
UUID=A1B2-C3D4 /home/user/app_data xfs defaults,noatime 0 2
UUID=5555-4444 none swap sw 0 0
EOF

    chmod -R 777 /home/user
