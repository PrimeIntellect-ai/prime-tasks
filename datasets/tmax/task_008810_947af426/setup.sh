#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_storage/node_alpha
    mkdir -p /home/user/raw_storage/node_beta
    mkdir -p /home/user/raw_storage/node_gamma
    mkdir -p /home/user/raw_storage/node_delta

    # Use /dev/zero instead of /dev/urandom for faster creation
    dd if=/dev/zero of=/home/user/raw_storage/node_alpha/data1.bin bs=1M count=10
    dd if=/dev/zero of=/home/user/raw_storage/node_beta/data2.bin bs=1M count=8
    dd if=/dev/zero of=/home/user/raw_storage/node_gamma/data3.bin bs=1M count=12
    dd if=/dev/zero of=/home/user/raw_storage/node_delta/data4.bin bs=1M count=5

    touch /home/user/raw_storage/node_gamma/.offline

    chmod -R 777 /home/user
