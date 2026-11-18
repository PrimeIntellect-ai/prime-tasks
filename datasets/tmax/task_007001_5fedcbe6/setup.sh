#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/staging_repo/batch1
    mkdir -p /home/user/staging_repo/batch2

    # Create valid archive 1 (zip)
    mkdir -p /tmp/arch1
    dd if=/dev/urandom of=/tmp/arch1/small.bin bs=1024 count=50 2>/dev/null
    dd if=/dev/urandom of=/tmp/arch1/large_v1.bin bs=1024 count=150 2>/dev/null
    cd /tmp/arch1 && zip -r /home/user/staging_repo/batch1/app_v1.zip . >/dev/null

    # Create valid archive 2 (tar.gz)
    mkdir -p /tmp/arch2
    dd if=/dev/urandom of=/tmp/arch2/large_v2.bin bs=1024 count=200 2>/dev/null
    cd /tmp/arch2 && tar -czf /home/user/staging_repo/batch2/app_v2.tar.gz . >/dev/null

    # Create valid archive 3 (zip with nested dirs)
    mkdir -p /tmp/arch3/subdir
    dd if=/dev/urandom of=/tmp/arch3/subdir/large_v3.bin bs=1024 count=120 2>/dev/null
    echo "readme" > /tmp/arch3/readme.txt
    cd /tmp/arch3 && zip -r /home/user/staging_repo/batch1/nested.zip . >/dev/null

    # Create corrupted archives
    echo "This is not a zip file" > /home/user/staging_repo/batch2/bad_data.zip
    echo "This is not a tarball" > /home/user/staging_repo/batch1/broken.tar.gz

    # Cleanup temp
    rm -rf /tmp/arch1 /tmp/arch2 /tmp/arch3

    chmod -R 777 /home/user
