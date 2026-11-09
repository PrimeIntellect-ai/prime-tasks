#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip p7zip-full g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset
    cd /home/user/dataset

    # Generate binary file
    python3 -c "
import struct
with open('measurements.bin', 'wb') as f:
    for i in range(1000):
        val = float(i * 0.1)
        # <IQf is little-endian: uint32, uint64, float
        f.write(struct.pack('<IQf', i, 1600000000+i, val))
"

    # Create dummy file to make the total size > 64k so zip -s 64k will actually split
    dd if=/dev/zero of=dummy.bin bs=1K count=100

    # Create multi-part zip (64KB parts, minimum allowed by standard zip)
    zip -s 64k archive.zip measurements.bin dummy.bin
    rm measurements.bin dummy.bin

    chmod -R 777 /home/user
