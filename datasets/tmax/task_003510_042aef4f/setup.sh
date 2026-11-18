#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    mkdir -p /home/user/src

    # Create data.bin using Python to ensure correct binary writing
    python3 -c "
with open('/home/user/data.bin', 'wb') as f:
    f.write(b'\x01\x04Rust\x02\x04\xe8\x07\x00\x00')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
