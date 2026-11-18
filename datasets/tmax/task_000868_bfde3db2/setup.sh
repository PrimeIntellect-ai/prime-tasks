#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_configs/serviceA
    mkdir -p /home/user/app_configs/serviceB
    mkdir -p /home/user/app_configs/serviceC
    mkdir -p /home/user/app_configs/serviceD/nested

    cat << 'EOF' > /home/user/app_configs/base.ini
[app]
name=BaseApp
version=1.0.0
[database]
port=5432
EOF

    cat << 'EOF' > /home/user/app_configs/shared.ini
[app]
name=SharedApp
version=1.1.5
EOF

    cat << 'EOF' > /home/user/app_configs/serviceC/config.ini
[system]
os=linux
[app]
version=2.0-beta
EOF

    cat << 'EOF' > /home/user/app_configs/serviceC/broken.ini
[system]
os=linux
version=9.9.9
EOF

    ln -s /home/user/app_configs/base.ini /home/user/app_configs/serviceA/config.ini
    ln -s /home/user/app_configs/shared.ini /home/user/app_configs/serviceD/nested/config.ini

    ln /home/user/app_configs/shared.ini /home/user/app_configs/serviceB/config.ini

    chmod -R 777 /home/user
