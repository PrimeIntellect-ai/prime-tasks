#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip e2tools
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil
    mkdir -p /app/services

    # Create evidence.img and use e2tools to insert and delete the payload without mounting
    dd if=/dev/zero of=/app/evidence.img bs=1M count=10
    mkfs.ext4 /app/evidence.img
    echo "DEADBEEF" > /tmp/payload.hex
    e2cp /tmp/payload.hex /app/evidence.img:/
    e2rm /app/evidence.img:/payload.hex
    rm /tmp/payload.hex

    # Generate clean corpus
    for i in $(seq 1 500); do
        echo "Clean payload data $i" > /app/corpus/clean/file_$i.txt
    done

    # Generate evil corpus
    for i in $(seq 1 500); do
        echo "EVIL_ padding_data_$i DEADBEEF" > /app/corpus/evil/file_$i.txt
    done

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
