#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev netcat-openbsd openssh-server openssh-client sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

    mkdir -p /run/sshd
    mkdir -p /home/user/.ssh
    mkdir -p /home/user/sensor_data
    mkdir -p /home/user/src

    ssh-keygen -t rsa -b 2048 -f /home/user/.ssh/iot_rsa -N ""
    cat /home/user/.ssh/iot_rsa.pub > /home/user/.ssh/authorized_keys
    chmod 600 /home/user/.ssh/authorized_keys

    cat << 'EOF' > /home/user/.ssh/config
Host localhost
    PubkeyAuthentication no
    IdentityFile /home/user/.ssh/wrong_key
EOF
    chmod 600 /home/user/.ssh/config

    echo "TEMP: 84.2C | HUMID: 41% | STATUS: NOMINAL" > /home/user/sensor_data/reading.txt

    chown -R user:user /home/user/.ssh /home/user/sensor_data /home/user/src

    # Start sshd when user logs in
    echo "sudo /usr/sbin/sshd 2>/dev/null || true" >> /home/user/.bashrc

    chmod -R 777 /home/user
