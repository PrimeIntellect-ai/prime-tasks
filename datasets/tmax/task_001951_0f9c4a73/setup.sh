#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc-bin
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_logs
    cd /home/user/legacy_logs

    # Create files in UTF-16LE
    echo -n "System startup successful." | iconv -f UTF-8 -t UTF-16LE > log_a.txt
    echo -n "Warning: Low disk space." | iconv -f UTF-8 -t UTF-16LE > log_b.txt
    echo -n "User admin logged in." | iconv -f UTF-8 -t UTF-16LE > log_c.txt
    echo -n "Error code 0x88F." | iconv -f UTF-8 -t UTF-16LE > log_d.txt

    # Set older timestamps for a and c
    touch -t 202301011000 log_a.txt
    touch -t 202301011000 log_c.txt

    # Create the timestamp file
    touch -t 202301021000 /home/user/last_backup.stamp

    # Set newer timestamps for b and d
    touch -t 202301031000 log_b.txt
    touch -t 202301031000 log_d.txt

    chown -R user:user /home/user/
    chmod -R 777 /home/user
