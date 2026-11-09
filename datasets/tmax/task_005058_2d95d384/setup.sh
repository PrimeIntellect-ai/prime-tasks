#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nodejs curl
    pip3 install pytest

    mkdir -p /home/user/app
    ln -s /etc/forbidden_conf /home/user/app/conf
    ln -s /var/log/forbidden_logs /home/user/app/logs

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
