#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar
    pip3 install pytest

    mkdir -p /home/user/raw_dataset
    cd /tmp
    mkdir -p region_A region_B

    # Region A Setup
    mkdir -p region_A/station_1 region_A/station_2
    echo "DATA_A1" > region_A/station_1/data_log.txt
    echo "DATA_A2" > region_A/station_2/data_log.txt
    cd region_A/station_1
    tar -czf ../station_1.tar.gz data_log.txt
    cd ../station_2
    zip ../station_2.zip data_log.txt
    cd ..
    zip /home/user/raw_dataset/region_A.zip station_1.tar.gz station_2.zip

    # Region B Setup
    cd /tmp
    mkdir -p region_B/station_3
    echo "DATA_B3" > region_B/station_3/data_log.txt
    cd region_B/station_3
    tar -czf ../station_3.tar.gz data_log.txt
    cd ..
    tar -czf /home/user/raw_dataset/region_B.tar.gz station_3.tar.gz

    rm -rf /tmp/region_A /tmp/region_B

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
