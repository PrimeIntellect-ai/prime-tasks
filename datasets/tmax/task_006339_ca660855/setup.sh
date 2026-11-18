#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data
    echo 'Q1 Revenue: $1000' > "/home/user/raw_data/Financial Report 2023.CSV"
    echo 'Discussed architecture.' > "/home/user/raw_data/Meeting notes.Txt"
    echo 'All systems operational.' > "/home/user/raw_data/daily_log.txt"

    chmod -R 777 /home/user
