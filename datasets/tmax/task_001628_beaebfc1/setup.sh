#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/monitor /home/user/protected_data
    echo "data1" > /home/user/protected_data/file1.txt
    echo "data2" > /home/user/protected_data/file2.txt

    chmod -R 777 /home/user
