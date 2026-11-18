#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import struct
import os

files = [
    (b"../../../etc/shadow", b"fake_shadow_data\n"),
    (b"/absolute/path/to/important.txt", b"hello world\n"),
    (b"normal_file.dat", b"normal data\n")
]

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/backup.bka", "wb") as f:
    for name, data in files:
        f.write(struct.pack("<H", len(name)))
        f.write(name)
        f.write(struct.pack("<I", len(data)))
        f.write(data)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
