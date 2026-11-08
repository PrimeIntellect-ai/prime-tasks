#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/raw_data
    mkdir -p /home/user/snapshots/v1

    # Create base dataset
    echo "data A" > /home/user/raw_data/unchanged1.txt
    echo "data B" > /home/user/raw_data/unchanged2.txt
    echo "data C" > /home/user/raw_data/modified1.txt
    echo "data D" > /home/user/raw_data/deleted1.txt

    # Set specific timestamps so mtime checks work predictably
    touch -t 202301011200 /home/user/raw_data/*.txt

    # Create v1 snapshot
    cp -a /home/user/raw_data/* /home/user/snapshots/v1/

    # Modify dataset for v2
    echo "data C modified" > /home/user/raw_data/modified1.txt
    touch -t 202301021200 /home/user/raw_data/modified1.txt

    rm /home/user/raw_data/deleted1.txt

    echo "data E" > /home/user/raw_data/new1.txt
    touch -t 202301031200 /home/user/raw_data/new1.txt
    echo "data F" > /home/user/raw_data/new2.txt
    touch -t 202301031200 /home/user/raw_data/new2.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
