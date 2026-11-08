#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/storage_nodes/node1
    mkdir -p /home/user/storage_nodes/node2
    mkdir -p /home/user/storage_nodes/node3
    mkdir -p /home/user/monitored_links
    mkdir -p /home/user/mail_spool

    dd if=/dev/urandom of=/home/user/storage_nodes/node1/data.bin bs=1M count=5 2>/dev/null
    dd if=/dev/urandom of=/home/user/storage_nodes/node2/data.bin bs=1M count=15 2>/dev/null
    dd if=/dev/urandom of=/home/user/storage_nodes/node3/data.bin bs=1M count=25 2>/dev/null

    ln -s /home/user/storage_nodes/node1 /home/user/monitored_links/app_data
    ln -s /home/user/storage_nodes/node2 /home/user/monitored_links/user_data
    ln -s /home/user/storage_nodes/node3 /home/user/monitored_links/backup_data
    ln -s /home/user/storage_nodes/nonexistent /home/user/monitored_links/legacy_data

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
