#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups
    mkdir -p /home/user/raw_configs/deep/path/to/some/nested/dirs
    mkdir -p /home/user/raw_configs/another/path/that/is/very/long

    printf "host=192.168.1.100\nport=5432\nuser=admin\n" > /home/user/raw_configs/deep/path/to/some/nested/dirs/old_db.conf
    printf "log_level=DEBUG\nworkers=4\nmax_connections=1024\n" > /home/user/raw_configs/another/path/that/is/very/long/old_web.conf
    printf "db.ini:host\nweb.ini:workers\n" > /home/user/rules.txt

    cd /home/user
    tar -cf configs.tar -C raw_configs deep/path/to/some/nested/dirs/old_db.conf another/path/that/is/very/long/old_web.conf
    tar -czf full.tar.gz configs.tar rules.txt

    split -b 1K full.tar.gz backups/split_archive.tar.gz.
    rm full.tar.gz configs.tar rules.txt
    rm -rf raw_configs

    chmod -R 777 /home/user
