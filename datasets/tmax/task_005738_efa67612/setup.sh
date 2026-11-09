#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_data /home/user/backups
    dd if=/dev/zero of=/home/user/app_data/db.sqlite bs=1024 count=1024

    chmod -R 777 /home/user
