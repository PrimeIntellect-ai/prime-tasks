#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc socat curl openssh-client openssh-server openssl
    pip3 install pytest

    # Setup sshd run directory
    mkdir -p /run/sshd

    # Create user
    useradd -m -s /bin/bash user || true

    # Ensure proper permissions
    chmod -R 777 /home/user
