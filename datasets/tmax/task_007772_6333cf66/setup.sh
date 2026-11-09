#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs/web
    mkdir -p /home/user/configs/database

    printf "listen=443\ntls=true" > /home/user/configs/web/server.conf
    printf "max_connections=1000\ntimeout=30s" > /home/user/configs/database/db.conf
    printf "debug=false\nlog_level=info" > /home/user/configs/main.conf
    printf "ignore me" > /home/user/configs/main.txt

    chown -R user:user /home/user/configs
    chmod -R 777 /home/user
