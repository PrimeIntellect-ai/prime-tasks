#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/filtered
    cd /home/user

    # Create configuration file
    echo "THRESHOLD=50" > config.ini

    # Create raw data for archives
    mkdir -p raw_data/a raw_data/b
    echo "10\n60\n20\n80" > raw_data/a/sensor1.txt
    echo "50\n51\n49\n100" > raw_data/a/sensor2.txt
    echo "200\n0\n10" > raw_data/b/sensor3.txt

    # Create nested archives
    cd raw_data/a
    tar -cvf ../../archive1.tar sensor1.txt sensor2.txt
    cd ../b
    tar -cvf ../../archive2.tar sensor3.txt
    cd ../../
    tar -czvf dataset_archive.tar.gz archive1.tar archive2.tar

    # Clean up temporary raw data
    rm -rf raw_data archive1.tar archive2.tar

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
