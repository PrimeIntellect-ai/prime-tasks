#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs
    mkdir -p /home/user/backups

    cat << 'EOF' > /home/user/configs/v1.conf
host=127.0.0.1
port=9090
password=oldsecret
token=oldtoken
user=guest
EOF

    cat << 'EOF' > /home/user/configs/v2.conf
host=localhost
port=8080
password=supersecret
token=abcdef
user=admin
EOF

    ln -s /home/user/configs/v2.conf /home/user/active.conf

    chown -R user:user /home/user/configs /home/user/backups /home/user/active.conf || true
    chmod -R 777 /home/user
