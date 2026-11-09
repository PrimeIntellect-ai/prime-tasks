#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/datasets
    mkdir -p /home/user/processed

    # Create binary files using python3 to avoid shell printf issues
    python3 -c 'open("/home/user/datasets/sample1.rle", "wb").write(b"\x05A\x03B\x02C")'
    python3 -c 'open("/home/user/datasets/data2.rle", "wb").write(b"\x04X\x04Y")'
    python3 -c 'open("/home/user/datasets/legacy.rle", "wb").write(b"\x03Z")'

    # Set legacy.rle mtime to 10 days ago
    touch -m -d "10 days ago" /home/user/datasets/legacy.rle

    chmod -R 777 /home/user
