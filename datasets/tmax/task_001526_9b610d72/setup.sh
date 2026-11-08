#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_configs/serviceA
    mkdir -p /home/user/app_configs/serviceB/nested
    mkdir -p /home/user/app_configs/serviceC

    cat << 'EOF' > /home/user/app_configs/serviceA/config.ini
[general]
name = serviceA
[auth_v1]
token_expiry = 3600
retry = 3
EOF

    cat << 'EOF' > /home/user/app_configs/serviceB/nested/settings.ini
[database]
host = localhost
[auth_v1]
token_expiry = 3600
EOF

    cat << 'EOF' > /home/user/app_configs/serviceC/config.ini
[general]
name = serviceC
[auth_v2]
token_expiry = 86400
EOF

    chmod -R 777 /home/user
