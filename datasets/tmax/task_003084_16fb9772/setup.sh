#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    echo -n "SECURE-CHALLENGE-9876543210" > /home/user/challenge.txt

    chmod -R 777 /home/user
