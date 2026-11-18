#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/data/logs
    mkdir -p /home/user/archive
    mkdir -p /home/user/staging

    # Active logs
    echo "User admin SECRET data" > /home/user/data/logs/app1.log
    echo "Nothing here to see" > /home/user/data/logs/app2.log
    echo "Another SECRET line" > /home/user/data/logs/app3.log
    ln -s /home/user/data/logs/app2.log /home/user/data/logs/current.log

    # Archives
    mkdir -p /tmp/legacy_dir
    echo "Old log data" > /tmp/legacy_dir/legacy.txt
    tar -czf /home/user/archive/legacy.tar.gz -C /tmp/legacy_dir legacy.txt
    echo "This is a corrupted archive" > /home/user/archive/broken.tar.gz

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
