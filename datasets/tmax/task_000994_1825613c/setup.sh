#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip bzip2
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/incoming
    mkdir -p /home/user/setup_tmp/app1
    mkdir -p /home/user/setup_tmp/app2
    mkdir -p /home/user/setup_tmp/app3

    # Create dummy binaries and files
    dd if=/dev/urandom of=/home/user/setup_tmp/app1/core_engine.bin bs=1K count=5 status=none
    dd if=/dev/urandom of=/home/user/setup_tmp/app1/libhelper.so bs=1K count=2 status=none
    echo "readme" > /home/user/setup_tmp/app1/readme.txt

    dd if=/dev/urandom of=/home/user/setup_tmp/app2/plugin.bin bs=1K count=3 status=none
    dd if=/dev/urandom of=/home/user/setup_tmp/app2/libnet.so bs=1K count=4 status=none

    dd if=/dev/urandom of=/home/user/setup_tmp/app3/corrupted_app.bin bs=1K count=1 status=none

    # Create valid archives
    cd /home/user/setup_tmp/app1
    tar -czf ../app1_valid.tar.gz .
    cd ../app2
    zip -r ../app2_valid.zip . > /dev/null

    # Create corrupted archive
    cd ../app3
    tar -czf ../app3_corrupt.tar.gz .
    # Corrupt it
    dd if=/dev/urandom of=../app3_corrupt.tar.gz bs=1K count=1 seek=1 conv=notrunc status=none

    # Package everything into the release batch
    cd /home/user/setup_tmp
    tar -cf /home/user/incoming/release_batch.tar app1_valid.tar.gz app2_valid.zip app3_corrupt.tar.gz

    # Cleanup setup tmp
    rm -rf /home/user/setup_tmp

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure permissions
    chmod -R 777 /home/user
