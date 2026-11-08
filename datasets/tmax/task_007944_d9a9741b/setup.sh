#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ jq
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import struct
import os

files = [
    (b"exp1.jsonl", b'{"id": 1, "v": 150}\n{"id": 3, "v": 200}\n'),
    (b"exp2.jsonl", b'{"id": 2, "v": 175}\n{"id": 4, "v": 220}\n')
]

out = bytearray(b"RDSF")
out += struct.pack("<I", len(files))
for name, data in files:
    name_padded = name.ljust(16, b'\x00')
    out += name_padded
    out += struct.pack("<I", len(data))
    out += data

# XOR with 0x5A
encrypted = bytearray([b ^ 0x5A for b in out])

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/research_data.bin", "wb") as f:
    f.write(encrypted)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
