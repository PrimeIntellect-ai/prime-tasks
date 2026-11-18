#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dumps

    cat << 'EOF' > /tmp/gen_dumps.py
import struct
import os
import random

dumps_dir = "/home/user/dumps"
magic = 0xDEADBEEF

files = [
    ("dump_01.bin", 1650000000, 1024),
    ("dump_02.bin", 1750000000, 2048),
    ("dump_03.bin", 1500000000, 512),
    ("dump_04.bin", 1700000000, 1024),
    ("dump_05.bin", 1699999999, 4096),
]

for fname, ts, size in files:
    path = os.path.join(dumps_dir, fname)
    with open(path, "wb") as f:
        f.write(struct.pack("<IIQ", magic, ts, size))
        f.write(os.urandom(size))
EOF

    python3 /tmp/gen_dumps.py
    rm /tmp/gen_dumps.py

    chown -R user:user /home/user/dumps
    chmod -R 777 /home/user
