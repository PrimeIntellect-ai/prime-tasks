#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip
    pip3 install pytest

    mkdir -p /home/user/configs
    mkdir -p /home/user/backups
    mkdir -p /tmp/backup_build

    # 1. Create original backup contents
    echo -n "port=8080" > /tmp/backup_build/app.conf
    echo -n "host=localhost" > /tmp/backup_build/db.conf
    echo -n "worker_processes 1;" > /tmp/backup_build/nginx.conf

    # Create nested archives
    cd /tmp/backup_build
    zip app.zip app.conf
    tar -czf db.tar.gz db.conf

    # Create the main archive with nested archives and one plain config
    tar -czf /home/user/backups/backup_v1.tar.gz app.zip db.tar.gz nginx.conf

    # 2. Create the current (live) configs
    echo -n "port=8080" > /home/user/configs/app.conf
    echo -n "host=127.0.0.1" > /home/user/configs/db.conf
    echo -n "worker_processes 1;" > /home/user/configs/nginx.conf
    echo -n "mode=prod" > /home/user/configs/new.conf

    # Cleanup
    rm -rf /tmp/backup_build

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
