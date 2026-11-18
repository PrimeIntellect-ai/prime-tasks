#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/data /home/user/backup_v1

    # Create initial files in data
    echo "stable data" > /home/user/data/file1.txt
    echo "unchanged data" > /home/user/data/file2.txt
    echo "new data v1" > /home/user/data/file3.txt

    # Create initial files in backup_v1
    echo "stable data" > /home/user/backup_v1/file1.txt
    echo "unchanged data" > /home/user/backup_v1/file2.txt

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
