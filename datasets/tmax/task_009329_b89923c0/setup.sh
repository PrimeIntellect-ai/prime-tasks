#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rsync tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/base_backup
    mkdir -p /home/user/final_data

    # Create base backup files
    echo "base log" > /home/user/base_backup/app_complete.log
    echo "old metric" > /home/user/base_backup/processed_metric_old.csv

    # Create corrupt tar file contents
    mkdir -p /tmp/tar_build/logs
    mkdir -p /tmp/tar_build/data
    mkdir -p /tmp/tar_build/evil

    echo "chunk1" > /tmp/tar_build/logs/app.log.aa
    echo "chunk2" > /tmp/tar_build/logs/app.log.ab
    echo "chunk3" > /tmp/tar_build/logs/app.log.ac

    echo "1,2,3" > /tmp/tar_build/data/metric_a1.data
    echo "4,5,6" > /tmp/tar_build/data/metric_b2.data

    echo "evil" > /tmp/tar_build/evil/outside.txt

    # Create the tar with path traversal
    cd /tmp/tar_build
    tar -cf /home/user/corrupt_data.tar logs/ data/
    # Append evil file with absolute path and ../ path
    tar -rf /home/user/corrupt_data.tar --transform='s|^|../|' logs/app.log.aa
    tar -rf /home/user/corrupt_data.tar --transform='s|^evil/outside.txt|/tmp/escaped.txt|' evil/outside.txt

    rm -rf /tmp/tar_build

    chmod -R 777 /home/user
