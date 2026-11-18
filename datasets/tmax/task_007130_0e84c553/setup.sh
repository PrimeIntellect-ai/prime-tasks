#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server golang curl iproute2 procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Fix sshd directory permissions to prevent startup errors
    mkdir -p /run/sshd
    chown root:root /run/sshd
    chmod 0755 /run/sshd

    # Set up passwordless SSH for 'user' to 'localhost'
    mkdir -p /home/user/.ssh
    chmod 700 /home/user/.ssh
    ssh-keygen -t ed25519 -f /home/user/.ssh/id_ed25519 -N ""
    cat /home/user/.ssh/id_ed25519.pub >> /home/user/.ssh/authorized_keys
    chmod 600 /home/user/.ssh/authorized_keys

    # Start SSH temporarily to run ssh-keyscan
    service ssh start
    sleep 2
    ssh-keyscan localhost >> /home/user/.ssh/known_hosts
    service ssh stop

    chown -R user:user /home/user/.ssh
    chmod -R 777 /home/user
