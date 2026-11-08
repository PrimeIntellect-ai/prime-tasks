#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset/train
    mkdir -p /home/user/dataset/val

    echo -n "apple banana" > /home/user/dataset/train/t1.txt
    echo -n "cat dog" > /home/user/dataset/train/t2.txt
    echo -n "elephant" > /home/user/dataset/train/t3.txt
    echo -n "grapefruit" > /home/user/dataset/train/t4.txt

    echo -n "apple" > /home/user/dataset/val/v1.txt
    echo -n "dog" > /home/user/dataset/val/v2.txt
    echo -n "zebra" > /home/user/dataset/val/v3.txt

    chmod -R 777 /home/user
