#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/backups

cat << 'EOF' > /tmp/setup_wal.py
import struct

def calc_checksum(data):
    return sum(data) % 256

records = [
    {
        "path": "/data/sys1.bin",
        "data": b'\x01\x02\x03\x04\x05',
        "valid": True
    },
    {
        "path": "/data/corrupt.bin",
        "data": b'\xAA\xBB\xCC',
        "valid": False  # We will write a bad checksum intentionally
    },
    {
        "path": "/data/config.cfg",
        "data": b'user=admin\npass=1234\n',
        "valid": True
    }
]

with open('/home/user/backups/db.wal', 'wb') as f:
    f.write(b"BKWAL1\n")
    for r in records:
        f.write(b"BEGIN\n")
        f.write(f"FILE: {r['path']}\n".encode('utf-8'))
        f.write(f"SIZE: {len(r['data'])}\n".format(len(r['data'])).encode('utf-8'))

        chk = calc_checksum(r['data'])
        if not r['valid']:
            chk = (chk + 1) % 256

        f.write(f"CHECKSUM: {chk:02X}\n".encode('utf-8'))
        f.write(b"DATA\n")
        f.write(r['data'])
        f.write(b"END\n")
EOF
python3 /tmp/setup_wal.py

chmod -R 777 /home/user
