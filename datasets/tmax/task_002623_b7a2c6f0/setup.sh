#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo
    pip3 install pytest websockets

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    cat << 'EOF' > /home/user/config_base.env
APP_VERSION=1.0.0
BUILD_THREADS=4
DEBUG=false
PLATFORM=android
EOF

    cat << 'EOF' > /home/user/config_override.env
DEBUG=true
SIGNING_KEY=prod.keystore
APP_VERSION=1.0.1
EOF

    chmod -R 777 /home/user
