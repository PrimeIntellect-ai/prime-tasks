#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts

    # Create app1.zip (staging -> production)
    mkdir -p /tmp/app1
    echo "VERSION=1.0\nSTATUS=staging\nAUTHOR=alice" > /tmp/app1/manifest.txt
    head -c 1024 </dev/urandom > /tmp/app1/data.bin
    cd /tmp/app1 && zip -r /home/user/artifacts/app1.zip manifest.txt data.bin

    # Create app2.tar.gz (staging -> production)
    mkdir -p /tmp/app2
    echo "VERSION=2.1\nSTATUS=staging\nAUTHOR=bob" > /tmp/app2/manifest.txt
    head -c 2048 </dev/urandom > /tmp/app2/data.bin
    cd /tmp/app2 && tar -czf /home/user/artifacts/app2.tar.gz manifest.txt data.bin

    # Create app3.zip (development -> unchanged)
    mkdir -p /tmp/app3
    echo "VERSION=1.5\nSTATUS=development\nAUTHOR=charlie" > /tmp/app3/manifest.txt
    head -c 512 </dev/urandom > /tmp/app3/data.bin
    cd /tmp/app3 && zip -r /home/user/artifacts/app3.zip manifest.txt data.bin

    # Create app4.tar.gz (production -> unchanged)
    mkdir -p /tmp/app4
    echo "VERSION=3.0\nSTATUS=production\nAUTHOR=diana" > /tmp/app4/manifest.txt
    head -c 1024 </dev/urandom > /tmp/app4/data.bin
    cd /tmp/app4 && tar -czf /home/user/artifacts/app4.tar.gz manifest.txt data.bin

    rm -rf /tmp/app1 /tmp/app2 /tmp/app3 /tmp/app4

    chmod -R 777 /home/user
