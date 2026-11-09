#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    # Generate the affinities.bin file
    python3 -c "
import struct
with open('/home/user/data/affinities.bin', 'wb') as f:
    val = 1.23456e-4
    f.write(struct.pack('<f', val) * 1000000)
"

    chmod -R 777 /home/user
