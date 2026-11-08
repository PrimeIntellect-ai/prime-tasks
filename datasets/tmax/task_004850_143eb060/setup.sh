#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/configs_v1/app
    mkdir -p /home/user/configs_v1/system
    mkdir -p /home/user/configs_v2/app
    mkdir -p /home/user/configs_v2/system

    printf "host=localhost\nport=5432\n" > /home/user/configs_v1/app/db.conf
    printf "workers=4\nport=80\n" > /home/user/configs_v1/app/web.conf
    printf "dns=8.8.8.8\n" > /home/user/configs_v1/system/network.conf

    printf "host=192.168.1.100\nport=5432\n" > /home/user/configs_v2/app/db.conf
    printf "workers=4\nport=80\n" > /home/user/configs_v2/app/web.conf
    printf "dns=1.1.1.1\n" > /home/user/configs_v2/system/network.conf
    printf "memory=1024\n" > /home/user/configs_v2/app/cache.conf

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
