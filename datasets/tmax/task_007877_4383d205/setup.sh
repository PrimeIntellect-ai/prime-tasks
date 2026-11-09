#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tzdata
    pip3 install pytest

    mkdir -p /home/user/cloud_storage/engineering
    mkdir -p /home/user/cloud_storage/marketing
    mkdir -p /home/user/cloud_storage/sales

    # Create files of exact sizes
    head -c 10485760 /dev/zero > /home/user/cloud_storage/engineering/data.bin
    head -c 5242880 /dev/zero > /home/user/cloud_storage/engineering/logs.txt
    head -c 2097152 /dev/zero > /home/user/cloud_storage/marketing/assets.zip
    head -c 3145728 /dev/zero > /home/user/cloud_storage/sales/leads.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
