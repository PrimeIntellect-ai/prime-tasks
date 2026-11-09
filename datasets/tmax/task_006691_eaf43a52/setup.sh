#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import struct
import gzip
import os

records = [
    (1680000000, b'A' * 1024),
    (1680000060, b'B' * 2048),
    (1680000120, b'C' * 512),
    (1680000180, b'D' * 4096)
]

data = bytearray()
for ts, payload in records:
    # Magic: 0x5A5A5A5A (1515870810)
    header = struct.pack('<I Q I', 0x5A5A5A5A, ts, len(payload))
    data.extend(header)
    data.extend(payload)

with gzip.open('/home/user/dataset.bin.gz', 'wb') as f:
    f.write(data)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
