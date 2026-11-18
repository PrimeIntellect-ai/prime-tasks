#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_logs
    head -c 12000 /dev/urandom > /home/user/app_logs/app.log
    head -c 2000 /dev/urandom > /home/user/app_logs/app.log.1
    head -c 1000 /dev/urandom > /home/user/app_logs/app.log.2

    chmod -R 777 /home/user
