#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/modules/core
    mkdir -p /home/user/modules/auth
    mkdir -p /home/user/modules/billing
    mkdir -p /home/user/modules/api
    mkdir -p /home/user/modules/frontend

    touch /home/user/modules/core/deps.txt

    echo "core" > /home/user/modules/auth/deps.txt

    echo "auth" > /home/user/modules/billing/deps.txt
    echo "core" >> /home/user/modules/billing/deps.txt

    echo "auth" > /home/user/modules/api/deps.txt
    echo "billing" >> /home/user/modules/api/deps.txt

    echo "api" > /home/user/modules/frontend/deps.txt
    echo "core" >> /home/user/modules/frontend/deps.txt

    chmod -R 777 /home/user
