#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct

os.makedirs("/home/user/storage_pool/backups", exist_ok=True)
os.makedirs("/home/user/storage_pool/misc", exist_ok=True)

def write_chunk(f, timestamp, filename, data):
    header = struct.pack("<4s Q I 16s", b"BLOB", timestamp, len(data), filename.encode('ascii'))
    f.write(header)
    f.write(data)

# Target File 1 (Large enough, > 1MB)
f1_path = "/home/user/storage_pool/backups/db_dump.blob"
with open(f1_path, "wb") as f:
    # Old chunk
    write_chunk(f, 1690000000, "old_data1.bin", b"A" * 500000)
    # New chunk (keep)
    write_chunk(f, 1710000000, "new_data1.bin", b"B" * 600000)

# Target File 2 (Large enough, > 1MB)
f2_path = "/home/user/storage_pool/misc/logs.blob"
with open(f2_path, "wb") as f:
    # New chunk (keep)
    write_chunk(f, 1705000000, "log_A.txt", b"C" * 800000)
    # Old chunk
    write_chunk(f, 1699999999, "log_B.txt", b"D" * 400000)
    # New chunk (keep)
    write_chunk(f, 1720000000, "log_C.txt", b"E" * 200000)

# Decoy File 1 (Small, < 1MB)
f3_path = "/home/user/storage_pool/misc/tiny.blob"
with open(f3_path, "wb") as f:
    write_chunk(f, 1710000000, "tiny.bin", b"F" * 1000)

# Decoy File 2 (Not a .blob)
f4_path = "/home/user/storage_pool/backups/archive.dat"
with open(f4_path, "wb") as f:
    write_chunk(f, 1710000000, "dat.bin", b"G" * 2000000)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
