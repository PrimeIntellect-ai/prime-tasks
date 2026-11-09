#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data
    python3 -c "
import struct
with open('/home/user/data/features.bin', 'wb') as f:
    f.write(struct.pack('<f', 2.0) * 1000000)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
