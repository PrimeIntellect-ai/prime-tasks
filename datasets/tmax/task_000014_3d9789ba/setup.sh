#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_datasets/batch1
    mkdir -p /home/user/raw_datasets/nested/batch2

    # Create dummy files for archive 1
    mkdir -p /tmp/a1
    touch /tmp/a1/2023-01-15_sensorA.csv
    touch /tmp/a1/2023-02-20_sensorB.json
    touch /tmp/a1/readme.txt
    tar -czf /home/user/raw_datasets/batch1/data1.tar.gz -C /tmp/a1 .

    # Create dummy files for archive 2
    mkdir -p /tmp/a2
    touch /tmp/a2/2022-11-05_sensorA.json
    touch /tmp/a2/2023-01-16_sensorC.csv
    touch /tmp/a2/photo.jpg
    cd /tmp/a2 && zip /home/user/raw_datasets/nested/batch2/data2.zip *

    # Create dummy files for archive 3
    mkdir -p /tmp/a3
    touch /tmp/a3/2022-12-25_sensorB.csv
    touch /tmp/a3/2022-12-26_sensorA.csv
    touch /tmp/a3/temp.tmp
    tar -cf /home/user/raw_datasets/data3.tar -C /tmp/a3 .

    rm -rf /tmp/a1 /tmp/a2 /tmp/a3

    chmod -R 777 /home/user
