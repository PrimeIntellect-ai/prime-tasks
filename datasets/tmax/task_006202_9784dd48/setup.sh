#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import random

random.seed(42)
os.makedirs('/home/user/raw_data', exist_ok=True)

valid_data = [
    ("alpha.bin", 1609459200, b"PROJ-A\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 123.4567), # 2021-01-01
    ("beta.bin", 1625097600, b"PROJ-B\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 987.6543), # 2021-07-01
    ("gamma.bin", 1640995200, b"PROJ-A\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 11.1111),   # 2022-01-01
]

# Create valid files
for i, (fname, ts, proj, metric) in enumerate(valid_data):
    d = os.path.join('/home/user/raw_data', f'subdir_{i}')
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, fname), 'wb') as f:
        f.write(struct.pack('<II16sd', 0xC0DEFEED, ts, proj, metric))

# Create invalid files
os.makedirs('/home/user/raw_data/invalid', exist_ok=True)
with open('/home/user/raw_data/invalid/bad_magic.bin', 'wb') as f:
    f.write(struct.pack('<II16sd', 0xDEADBEEF, 1609459200, b"PROJ-X\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 1.23))

with open('/home/user/raw_data/invalid/too_short.bin', 'wb') as f:
    f.write(b"short")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chown -R user:user /home/user/raw_data
    chmod -R 777 /home/user
