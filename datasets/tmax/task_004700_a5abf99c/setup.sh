#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data_to_backup/logs
    mkdir -p /home/user/data_to_backup/binaries/old_fw
    mkdir -p /home/user/data_to_backup/configs

    echo "User login failed: admin" > /home/user/data_to_backup/logs/auth.log
    echo "INFO: Application started" > /home/user/data_to_backup/logs/app.log
    echo "server=127.0.0.1" > /home/user/data_to_backup/configs/db.txt

    dd if=/dev/urandom of=/home/user/data_to_backup/binaries/core.bin bs=1024 count=5 2>/dev/null
    dd if=/dev/urandom of=/home/user/data_to_backup/binaries/old_fw/v1.dat bs=1024 count=2 2>/dev/null

    chown -R user:user /home/user/data_to_backup

    chmod -R 777 /home/user
