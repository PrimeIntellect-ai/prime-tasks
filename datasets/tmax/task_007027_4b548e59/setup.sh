#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.ssh
    echo "Host *" > /home/user/.ssh/config
    echo "    PubkeyAuthentication no" >> /home/user/.ssh/config
    echo "    IdentityFile ~/.ssh/id_rsa" >> /home/user/.ssh/config

    mkdir -p /home/user/deploy/releases/v1.0

    chmod -R 777 /home/user
