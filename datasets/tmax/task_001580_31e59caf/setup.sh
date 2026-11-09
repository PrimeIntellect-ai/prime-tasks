#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/source_data/logs
    mkdir -p /home/user/source_data/config
    mkdir -p /home/user/source_data/media

    # Create small files
    echo "log entry 1" > /home/user/source_data/logs/app1.log
    echo "server=127.0.0.1" > /home/user/source_data/config/server.ini
    echo "mode=production" > /home/user/source_data/config/env.ini

    # Create large files
    dd if=/dev/urandom of=/home/user/source_data/logs/large_app.log bs=1024 count=1500 status=none
    dd if=/dev/urandom of=/home/user/source_data/media/image.bin bs=1024 count=2000 status=none

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/source_data
    chmod -R 777 /home/user
