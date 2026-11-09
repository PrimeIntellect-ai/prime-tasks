#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssh-server openssh-client netcat-openbsd curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Prepare sshd environment
    mkdir -p /var/run/sshd
    chmod 0755 /var/run/sshd

    chmod -R 777 /home/user
