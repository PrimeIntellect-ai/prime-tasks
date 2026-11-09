#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        redis-server \
        nginx \
        gcc \
        make \
        libcjson-dev \
        libjansson-dev \
        libtar-dev \
        zlib1g-dev \
        libhiredis-dev \
        curl \
        wget

    pip3 install pytest redis requests

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_data/dir1/dir2
    mkdir -p /home/user/legacy_data/dir3
    mkdir -p /home/user/www

    echo "timestamp,sensor_id,value\n1600000000,1,10.5\n1600000001,1,11.0" > /home/user/legacy_data/dir1/dir2/data1.csv
    echo "timestamp,sensor_id,value\n1600000002,2,20.0\n1600000003,2,21.5" > /home/user/legacy_data/dir3/data2.csv
    echo "timestamp,sensor_id,value\n1600000004,3,5.0" > /home/user/legacy_data/data3.csv

    chmod -R 777 /home/user
