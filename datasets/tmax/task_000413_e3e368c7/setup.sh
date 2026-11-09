#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct

base_dir = "/home/user/backups"
os.makedirs(os.path.join(base_dir, "server_alpha"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "server_beta"), exist_ok=True)
os.makedirs(os.path.join(base_dir, "server_gamma"), exist_ok=True)

backups = [
    {
        "id": "BK-A01",
        "path": "server_alpha/sys1.bin",
        "offset": 512,
        "magic": b'\xBA\xAD\xF0\x0D',
        "timestamp": 1680307200
    },
    {
        "id": "BK-B01",
        "path": "server_beta/db_dump.bin",
        "offset": 1024,
        "magic": b'\xC0\xFF\xEE\x11',
        "timestamp": 1680393600
    },
    {
        "id": "BK-G01",
        "path": "server_gamma/app_data.bin",
        "offset": 2048,
        "magic": b'\x0B\xAD\xC0\xDE',
        "timestamp": 1680480000
    }
]

csv_content = "BackupID,RelativePath,HeaderOffset\n"

for bk in backups:
    csv_content += f"{bk['id']},{bk['path']},{bk['offset']}\n"

    file_path = os.path.join(base_dir, bk['path'])

    file_size = bk['offset'] + 100
    data = bytearray(os.urandom(file_size))

    data[bk['offset']:bk['offset']+4] = bk['magic']

    ts_bytes = struct.pack("<I", bk['timestamp'])
    data[bk['offset']+4:bk['offset']+8] = ts_bytes

    with open(file_path, "wb") as f:
        f.write(data)

with open(os.path.join(base_dir, "index.csv"), "w") as f:
    f.write(csv_content)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
