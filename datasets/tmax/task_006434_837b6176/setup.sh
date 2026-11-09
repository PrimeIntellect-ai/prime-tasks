#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git openssh-client
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dashboards.git
    cd /home/user/dashboards.git && git init --bare

    mkdir -p /home/user/.ssh
    mkdir -p /home/user/dashboards_backup

    chmod -R 777 /home/user
    chmod 700 /home/user/.ssh
