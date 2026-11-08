#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl openssl tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data_dir
    mkdir -p /home/user/backup_dir
    mkdir -p /home/user/certs

    dd if=/dev/urandom of=/home/user/data_dir/large_file.dat bs=1M count=60

    chmod -R 777 /home/user
