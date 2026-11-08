#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/configs/db
    mkdir -p /home/user/configs/web
    mkdir -p /home/user/configs/cache

    cat << 'EOF' > /tmp/setup.py
import os

def create_bak(path, text, valid_checksum=True):
    # text is a string, we encode to ISO-8859-1
    encoded = text.encode('iso-8859-1')

    # Simple RLE
    rle_data = bytearray()
    checksum = 0
    for byte in encoded:
        rle_data.append(1) # count = 1
        rle_data.append(byte)
        checksum = (checksum + byte) % 256

    if not valid_checksum:
        checksum = (checksum + 1) % 256 # Corrupt it

    with open(path, 'wb') as f:
        f.write(rle_data)
        f.write(bytes([checksum]))

create_bak('/home/user/configs/db/node1.bak', 'USER=admin\nTRACKED_CHANGE=schema_v5\nPORT=5432\n')
create_bak('/home/user/configs/web/front.bak', 'WORKERS=4\nTRACKED_CHANGE=£50_bonus_promo\nENV=prod\n')
create_bak('/home/user/configs/cache/redis.bak', 'MAX_MEM=2G\nTRACKED_CHANGE=corrupted_update\n', valid_checksum=False)
create_bak('/home/user/configs/db/node2.bak', 'USER=read_only\nTRACKED_CHANGE=schema_v5_replica\n')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
