#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron curl openssl coreutils
    pip3 install pytest aiosmtpd
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
