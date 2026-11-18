#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/target_sshd_config
# This is a mock sshd_config
Port 22
ListenAddress 0.0.0.0
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication yes
X11Forwarding no
EOF

    echo -n "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" > /home/user/aes_key.txt

    chown -R user:user /home/user
    chmod -R 777 /home/user
