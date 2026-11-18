#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct

def write_wal(path, records):
    with open(path, 'wb') as f:
        f.write(b'WALv1\0\0\0')
        for ts, op, obj_id, payload in records:
            f.write(struct.pack('<QBII', ts, op, obj_id, len(payload)))
            f.write(payload)

os.makedirs('/home/user/wal_archive', exist_ok=True)

# Op types: 1=INSERT, 2=UPDATE, 3=DROP
# wal_1.wal
write_wal('/home/user/wal_archive/wal_1.wal', [
    (1000001, 1, 100, b'data100'),
    (1000002, 3, 404, b''),
    (1000003, 2, 100, b'data100_v2')
])

# wal_2.wal
write_wal('/home/user/wal_archive/wal_2.wal', [
    (1000004, 3, 12, b''),
    (1000005, 1, 500, b'data500'*10),
    (1000006, 3, 999, b'reason')
])

# wal_3.wal
write_wal('/home/user/wal_archive/wal_3.wal', [
    (1000007, 3, 404, b''), # duplicate drop id
    (1000008, 1, 888, b'hello'),
    (1000009, 3, 777, b'')
])
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
