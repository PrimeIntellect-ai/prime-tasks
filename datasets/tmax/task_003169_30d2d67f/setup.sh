#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset/train/spam
    mkdir -p /home/user/dataset/train/ham
    mkdir -p /home/user/dataset/test/spam
    mkdir -p /home/user/dataset/test/ham

    echo "buy now!!" > /home/user/dataset/train/spam/1.txt
    echo "click here for free money" > /home/user/dataset/train/spam/2.txt
    echo "cheap watches, buy buy" > /home/user/dataset/train/spam/3.txt

    echo "hello friend" > /home/user/dataset/train/ham/1.txt
    echo "meeting at 10 tomorrow" > /home/user/dataset/train/ham/2.txt
    echo "lunch tomorrow?" > /home/user/dataset/train/ham/3.txt

    echo "free money now" > /home/user/dataset/test/spam/1.txt
    echo "click for watches" > /home/user/dataset/test/spam/2.txt

    echo "see you at lunch" > /home/user/dataset/test/ham/1.txt
    echo "hello meeting" > /home/user/dataset/test/ham/2.txt

    chmod -R 777 /home/user
