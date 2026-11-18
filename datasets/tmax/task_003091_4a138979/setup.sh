#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    echo -n "3132352a34" > /home/user/payload.txt
    chmod 644 /home/user/payload.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
