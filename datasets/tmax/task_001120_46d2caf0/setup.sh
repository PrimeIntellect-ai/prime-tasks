#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import struct
import os

wal_path = '/home/user/db.wal'
os.makedirs(os.path.dirname(wal_path), exist_ok=True)

with open(wal_path, 'wb') as f:
    f.write(b'WAL!')
    for txid in range(1, 51):
        char1 = chr(65 + (txid % 26))
        char2 = chr(65 + ((txid + 1) % 26))
        count1 = txid
        count2 = txid + 2
        payload = (char1 * count1) + (char2 * count2)
        payload_bytes = payload.encode('ascii')
        length = len(payload_bytes)
        f.write(struct.pack('<II', txid, length))
        f.write(payload_bytes)
    f.write(struct.pack('<II', 51, 100))
    f.write(b'INCOM')
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
