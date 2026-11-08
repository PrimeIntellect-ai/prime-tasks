#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/live_dataset
    mkdir -p /home/user/backups

    # Create initial data
    echo "chunk1" > /home/user/live_dataset/data1.csv
    echo "chunk2" > /home/user/live_dataset/data2.csv

    # Create full backup
    cd /home/user/live_dataset
    tar -czf /home/user/backups/full_backup.tar.gz data1.csv data2.csv

    # Simulate time passing
    sleep 2

    # Modify existing file and add new file (Simulating live data stream)
    echo "chunk1_appended" >> /home/user/live_dataset/data1.csv
    echo "chunk3" > /home/user/live_dataset/data3.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
