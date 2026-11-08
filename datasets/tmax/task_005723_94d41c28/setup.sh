#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/sysapp/mail
    mkdir -p /home/user/sysconfig

    # Create .bashrc
    touch /home/user/.bashrc

    # Create initial config file
    cat << 'EOF' > /home/user/sysconfig/smtp_production.ini
[smtp]
bind_address = mail.internal.local
port = 25
EOF

    # Set permissions
    chmod -R 777 /home/user
