#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_configs

    echo -e "[Network]\nIP=192.168.1.10\n[Database]\nDB_PASSWORD=secret123\n" | iconv -f UTF-8 -t UTF-16LE | gzip -c > /home/user/legacy_configs/node_A.cfg.gz
    echo -e "[Network]\nIP=192.168.1.11\n[Database]\nDB_PASSWORD=super_secure\n" | iconv -f UTF-8 -t UTF-16LE | gzip -c > /home/user/legacy_configs/node_B.cfg.gz
    echo -e "[Network]\nIP=192.168.1.12\n[Database]\nDB_PASSWORD=adminPass\n" | iconv -f UTF-8 -t UTF-16LE | gzip -c > /home/user/legacy_configs/node_C.cfg.gz

    chmod -R 777 /home/user
