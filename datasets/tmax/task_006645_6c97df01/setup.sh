#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential gzip
    pip3 install pytest

    mkdir -p /home/user/active_logs/b
    echo "aaaabbbbcc" > /home/user/active_logs/a.log
    echo "xxxxxxxxxxx" > /home/user/active_logs/b/c.log
    echo "yy" >> /home/user/active_logs/b/c.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
