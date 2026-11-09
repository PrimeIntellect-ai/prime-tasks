#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libssl-dev tar coreutils
    pip3 install pytest

    mkdir -p /home/user/incoming
    mkdir -p /home/user/backup
    mkdir -p /home/user/src
    mkdir -p /home/user/bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
