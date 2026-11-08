#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create task directories and files
    mkdir -p /home/user/app_data
    echo "dummy data" > /home/user/app_data/data1.txt
    echo "more data" > /home/user/app_data/data2.txt
    touch /home/user/.bashrc

    # Set permissions
    chmod -R 777 /home/user
