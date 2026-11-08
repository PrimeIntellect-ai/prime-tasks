#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/s3_cache/alpha
    mkdir -p /home/user/s3_cache/beta
    mkdir -p /home/user/s3_cache/gamma
    mkdir -p /home/user/s3_cache/delta

    # Create files of specific sizes
    dd if=/dev/urandom of=/home/user/s3_cache/alpha/data.bin bs=1M count=5
    dd if=/dev/urandom of=/home/user/s3_cache/beta/data.bin bs=1M count=15
    dd if=/dev/urandom of=/home/user/s3_cache/gamma/data.bin bs=1M count=12
    dd if=/dev/urandom of=/home/user/s3_cache/delta/data.bin bs=1M count=8

    # Set permissions
    chmod -R 777 /home/user
