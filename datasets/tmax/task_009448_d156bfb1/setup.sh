#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc jq gawk
    pip3 install pytest

    mkdir -p /home/user/src
    head -c 1024 /dev/urandom > /home/user/src/binary.dat
    seq 1 50 > /home/user/src/script.sh
    seq 1 100 > /home/user/src/app.py
    echo "Hello World" > /home/user/src/readme.md

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
