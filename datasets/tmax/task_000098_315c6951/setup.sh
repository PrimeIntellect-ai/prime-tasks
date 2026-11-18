#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_repo

    cat << 'EOF' > /tmp/setup.py
import os
import struct

os.makedirs('/home/user/legacy_repo', exist_ok=True)

# 1. Create artifacts.artf
files_to_pack = {
    "app_config.cfg": b"auth_protocol=v1\nmirror=http://old.repo.local\ndeprecated_flag=true\nsetting=42\n",
    "db_config.cfg": b"host=localhost\nauth_protocol=v1\ndeprecated_flag=1\nmirror=http://old.repo.local\n",
    "binary_blob.dat": b"\x00\x00\x00\xFF\xFF\xFF\x00\x00\x00"
}

def compress_rle(data):
    compressed = bytearray()
    i = 0
    while i < len(data):
        count = 1
        while i + count < len(data) and data[i] == data[i + count] and count < 255:
            count += 1
        compressed.append(count)
        compressed.append(data[i])
        i += count
    return compressed

with open('/home/user/legacy_repo/artifacts.artf', 'wb') as f:
    f.write(b"ARTF")
    f.write(struct.pack("<H", len(files_to_pack)))

    for filename, data in files_to_pack.items():
        compressed = compress_rle(data)
        f.write(struct.pack("B", len(filename)))
        f.write(filename.encode('ascii'))
        f.write(struct.pack("<I", len(data)))
        f.write(struct.pack("<I", len(compressed)))
        f.write(compressed)

# 2. Create index.bin
index_records = [
    (b"app_config.cfg", 391203, 1690000000),
    (b"db_config.cfg", 849201, 1690000100),
    (b"binary_blob.dat", 112233, 1690000200)
]

with open('/home/user/legacy_repo/index.bin', 'wb') as f:
    for name, checksum, timestamp in index_records:
        padded_name = name.ljust(16, b'\x00')
        f.write(padded_name)
        f.write(struct.pack("<I", checksum))
        f.write(struct.pack("<I", timestamp))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
