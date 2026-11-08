#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import struct
import os

def rle_encode(data: bytes) -> bytes:
    encoded = bytearray()
    i = 0
    while i < len(data):
        count = 1
        while i + count < len(data) and data[i] == data[i+count] and count < 255:
            count += 1
        encoded.append(count)
        encoded.append(data[i])
        i += count
    return bytes(encoded)

def create_entry(path: str, data: bytes) -> bytes:
    path_bytes = path.encode('ascii')
    path_len = len(path_bytes)
    compressed_data = rle_encode(data)
    compressed_size = len(compressed_data)

    entry = struct.pack('<B', path_len)
    entry += path_bytes
    entry += struct.pack('<I', compressed_size)
    entry += compressed_data
    return entry

caf_data = b'CAF\x01'

# Valid CSV
csv_content = b"id,artifact_name,checksum\n1,kernel_mod,a1b2c3d4\n2,libssl_custom,f9e8d7c6\n"
caf_data += create_entry("artifacts.csv", csv_content)

# Malicious file
malicious_content = b"YOU HAVE BEEN HACKED!"
caf_data += create_entry("../secret_overwrite.txt", malicious_content)

# Valid binary
bin_content = b"\x00\x00\x00\x00\xFF\xFF\xFF\xFF" * 10
caf_data += create_entry("binary.bin", bin_content)

with open("/home/user/repo.caf", "wb") as f:
    f.write(caf_data)

with open("/home/user/secret_overwrite.txt", "w") as f:
    f.write("SAFE")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
