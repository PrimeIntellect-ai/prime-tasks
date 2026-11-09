#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest aiosmtpd

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/staging
    mkdir -p /home/user/production
    mkdir -p /home/user/backup

    touch /home/user/staging/app_v2.py
    touch /home/user/staging/config.yml
    touch /home/user/production/app_v1.py

    chmod -R 777 /home/user
