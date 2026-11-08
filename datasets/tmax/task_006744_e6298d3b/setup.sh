#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/data/logs
    mkdir -p /home/user/data/backups

    # Create files of specific sizes
    head -c 2000 /dev/urandom > /home/user/data/logs/small.log
    head -c 5000 /dev/urandom > /home/user/data/logs/medium.log
    head -c 8000 /dev/urandom > /home/user/data/logs/large.log
    head -c 10000 /dev/urandom > /home/user/data/backups/old.bak
    head -c 20000 /dev/urandom > /home/user/data/backups/new.bak

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
