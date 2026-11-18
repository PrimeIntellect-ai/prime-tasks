#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang expect curl netcat-openbsd
    pip3 install pytest

    mkdir -p /home/user/src
    mkdir -p /home/user/scripts
    mkdir -p /home/user/deploy/v1
    mkdir -p /home/user/deploy/v2
    mkdir -p /home/user/mail/new

    touch /home/user/deploy/v1/app
    chmod +x /home/user/deploy/v1/app
    ln -s /home/user/deploy/v1 /home/user/deploy/current

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
