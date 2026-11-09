#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/logs_source /home/user/staging /home/user/backups

    # Create files with specific sizes and modification dates
    dd if=/dev/urandom of=/home/user/logs_source/db.log bs=1024 count=15
    touch -d "2023-10-01 12:00:00" /home/user/logs_source/db.log

    dd if=/dev/urandom of=/home/user/logs_source/web.log bs=1024 count=20
    touch -d "2023-10-02 12:00:00" /home/user/logs_source/web.log

    dd if=/dev/urandom of=/home/user/logs_source/api.log bs=1024 count=5
    touch -d "2023-10-03 12:00:00" /home/user/logs_source/api.log

    dd if=/dev/urandom of=/home/user/logs_source/app.log bs=1024 count=12
    touch -d "2023-10-04 12:00:00" /home/user/logs_source/app.log

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
