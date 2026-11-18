#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/etc_mock/app1
    mkdir -p /home/user/etc_mock/nginx/conf.d
    mkdir -p /home/user/snapshots

    # Old files (> 24h)
    echo "host=localhost" > /home/user/etc_mock/app1/old.conf
    touch -m -d "2 days ago" /home/user/etc_mock/app1/old.conf
    echo "user=root" > /home/user/etc_mock/old_root.conf
    touch -m -d "3 days ago" /home/user/etc_mock/old_root.conf

    # New files (< 24h)
    echo "db=postgres" > /home/user/etc_mock/app1/db.conf
    echo "server { listen 80; }" > /home/user/etc_mock/nginx/nginx.conf
    echo "ignore this" > /home/user/etc_mock/nginx/not_a_conf.txt

    chmod -R 777 /home/user
