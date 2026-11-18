#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/cloud_storage/bucketA
    mkdir -p /home/user/cloud_storage/bucketB
    mkdir -p /home/user/cloud_storage/bucket_missing

    cat << 'EOF' > /home/user/storage_config.txt
/home/user/cloud_storage/bucketA
/home/user/cloud_storage/bucket_missing
/home/user/cloud_storage/bucketB
EOF

    dd if=/dev/zero of=/home/user/cloud_storage/bucketA/small1.txt bs=1 count=50000
    dd if=/dev/zero of=/home/user/cloud_storage/bucketA/large1.bin bs=1 count=150000

    dd if=/dev/zero of=/home/user/cloud_storage/bucketB/small2.txt bs=1 count=99999
    dd if=/dev/zero of=/home/user/cloud_storage/bucketB/large2.bin bs=1 count=200000

    chown -R user:user /home/user/cloud_storage
    chown user:user /home/user/storage_config.txt

    chmod -R 777 /home/user
