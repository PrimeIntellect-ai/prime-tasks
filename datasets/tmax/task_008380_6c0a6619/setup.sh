#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx curl
    pip3 install pytest

    mkdir -p /home/user/src \
             /home/user/data \
             /home/user/nginx \
             /home/user/bin \
             /home/user/run \
             /home/user/nginx/tmp

    echo "Hello World" > /home/user/data/file1.txt
    echo "Test data for storage" > /home/user/data/file2.txt
    dd if=/dev/zero of=/home/user/data/file3.bin bs=1 count=1024

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
