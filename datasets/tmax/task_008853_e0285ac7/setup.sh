#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/config_tree/appA
    mkdir -p /home/user/config_tree/appB
    mkdir -p /home/user/config_tree/appC

    # Normal files
    echo "config data" > /home/user/config_tree/appA/config.ini
    dd if=/dev/urandom of=/home/user/config_tree/appC/data.bin bs=1K count=1 2>/dev/null

    # Normal symlink
    ln -s /home/user/config_tree/appA/config.ini /home/user/config_tree/appA/config_link.ini

    # Looping symlink pair 1
    ln -s /home/user/config_tree/appB/loop2 /home/user/config_tree/appB/loop1
    ln -s /home/user/config_tree/appB/loop1 /home/user/config_tree/appB/loop2

    # Self-looping symlink 2
    ln -s loop_self /home/user/config_tree/appC/loop_self

    chmod -R 777 /home/user
