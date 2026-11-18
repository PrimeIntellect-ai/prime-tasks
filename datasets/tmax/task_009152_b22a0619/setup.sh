#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    echo -n "ACGCGCATAT" > /home/user/sequence.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
