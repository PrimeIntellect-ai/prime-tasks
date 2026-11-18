#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev make
    pip3 install pytest

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/auth.log
2023-10-01T12:00:00Z auth_service: user=admin password=strongpass src_ip=192.168.1.50 status=success
2023-10-01T12:05:00Z auth_service: user=dev password=hunter2 src_ip=10.0.0.15 status=success
2023-10-01T12:10:00Z auth_service: user=guest password=guest src_ip=172.16.0.4 status=failed
2023-10-01T12:15:00Z auth_service: user=root password=hunter2 src_ip=198.51.100.22 status=failed
2023-10-01T12:20:00Z auth_service: user=dev password=hunter2 src_ip=10.0.0.15 status=success
2023-10-01T12:25:00Z auth_service: user=test password=hunter1 src_ip=10.0.0.16 status=failed
EOF

    echo -n "SuperSecretRotatedKey123!" > /home/user/workspace/new_secret.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
