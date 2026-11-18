#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go zip unzip tar coreutils
    pip3 install pytest

    mkdir -p /home/user/raw_logs/server1
    mkdir -p /home/user/raw_logs/server2
    mkdir -p /home/user/processed

    # Create dummy logs
    for i in {1..50}; do echo "2023-10-01 10:00:0$i INFO Connection from 192.168.1.100 accepted" >> /home/user/raw_logs/server1/app.log; done
    for i in {1..30}; do echo "2023-10-01 10:01:0$i ERROR Timeout from 10.0.0.5" >> /home/user/raw_logs/server1/app.log; done
    for i in {1..40}; do echo "2023-10-01 10:02:0$i WARN Retrying 192.168.1.100" >> /home/user/raw_logs/server2/db.log; done

    cd /home/user/raw_logs/server1 && zip -r /home/user/server1.zip ./*
    cd /home/user/raw_logs/server2 && zip -r /home/user/server2.zip ./*
    cd /home/user && tar -czf backup.tar.gz server1.zip server2.zip
    rm -rf /home/user/raw_logs /home/user/server1.zip /home/user/server2.zip

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
