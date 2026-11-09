#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev jq tar gzip
    pip3 install pytest

    mkdir -p /home/user/source_configs
    echo "port=8080" > /home/user/source_configs/web.conf
    echo "db_host=localhost" > /home/user/source_configs/db.conf
    echo "cache_size=1024" > /home/user/source_configs/cache.conf

    cd /home/user/source_configs && tar -cf /home/user/configs.tar web.conf db.conf cache.conf
    rm -rf /home/user/source_configs

    mkdir -p /home/user/config_tree
    ln -s /home/user/extracted_configs/web.conf /home/user/config_tree/active_web
    ln -s /home/user/extracted_configs/db.conf /home/user/config_tree/active_db
    ln -s /home/user/extracted_configs/missing.conf /home/user/config_tree/active_missing

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
