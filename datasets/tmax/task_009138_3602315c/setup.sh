#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest hypothesis

    mkdir -p /home/user/project
    mkdir -p /home/user/libs

    mkdir -p /home/user/libs/libAlpha-1.0.0
    mkdir -p /home/user/libs/libAlpha-1.2.0
    mkdir -p /home/user/libs/libAlpha-1.2.5
    mkdir -p /home/user/libs/libAlpha-2.0.0
    mkdir -p /home/user/libs/libBeta-0.9.0
    mkdir -p /home/user/libs/libBeta-1.1.0
    mkdir -p /home/user/libs/libBeta-1.1.2

    cat << 'EOF' > /home/user/project/link_config.txt
libAlpha >=1.1.0,<2.0.0
libBeta >=1.0.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
