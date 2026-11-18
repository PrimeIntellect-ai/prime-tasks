#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import struct
import gzip
import os

def create_archive(filepath):
    files = [
        {"name": "readme.txt", "data": b"This is a test readme.", "comp": 0},
        {"name": "libmath.so", "data": b"\x7FELF_MOCK_MATH_DATA_9921", "comp": 1},
        {"name": "config.json", "data": b'{"env": "prod"}', "comp": 1},
        {"name": "libutils.so", "data": b"\x7FELF_MOCK_UTILS_DATA_4455\x00\x01\x02", "comp": 0}
    ]

    with open(filepath, 'wb') as f:
        f.write(b'ARTF')
        f.write(struct.pack('<I', len(files)))

        for file in files:
            name_bytes = file["name"].encode('utf-8')
            orig_data = file["data"]

            if file["comp"] == 1:
                comp_data = gzip.compress(orig_data)
            else:
                comp_data = orig_data

            f.write(struct.pack('<H', len(name_bytes)))
            f.write(name_bytes)
            f.write(struct.pack('<I', len(comp_data)))
            f.write(struct.pack('<I', len(orig_data)))
            f.write(struct.pack('<B', file["comp"]))
            f.write(comp_data)

if __name__ == "__main__":
    os.makedirs("/home/user", exist_ok=True)
    create_archive("/home/user/artifacts.bin")
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
