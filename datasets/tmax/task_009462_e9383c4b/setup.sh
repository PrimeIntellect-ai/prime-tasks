#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl socat openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_v1
    echo "legacy data" > /home/user/app_v1/data.txt
    touch /home/user/deploy.log

    chmod -R 777 /home/user
