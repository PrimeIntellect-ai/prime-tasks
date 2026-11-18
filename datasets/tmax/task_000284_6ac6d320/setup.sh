#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user/extracted

cat << 'EOF' > /tmp/setup.py
import struct
import os

records = [
    (b"000000000001", b"SOMEDATA_CONFIRMED_DATA12"),
    (b"000000000002", b"SOMEDATA_REJECTED_DATA"),
    (b"000000000003", b"CONFIRMED_START"),
    (b"000000000004", b"PENDING_WAITING"),
    (b"000000000005", b"ANOTHER_CONFIRMED_ITEM")
]

with open('/home/user/repository.bin', 'wb') as f:
    for r_id, r_data in records:
        f.write(b"ARTF")
        f.write(r_id)
        f.write(struct.pack("<I", len(r_data)))
        xored_data = bytes(b ^ 0x42 for b in r_data)
        f.write(xored_data)
        f.write(b"DONE")
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
