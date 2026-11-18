#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import random

random.seed(42)

base_dir = "/home/user/sensor_archives"
os.makedirs(base_dir, exist_ok=True)
os.makedirs(os.path.join(base_dir, "subdir"), exist_ok=True)

def create_record(sensor_id, ts, length):
    magic = 0xDEADBEEF
    header = struct.pack("<IHIH", magic, sensor_id, ts, length)
    # Payload is just zeros to ensure no accidental magic numbers
    payload = b'\x00' * length
    return header + payload

# File 1: Valid size (> 4096), contains records
f1_path = os.path.join(base_dir, "data1.log")
with open(f1_path, "wb") as f:
    f.write(os.urandom(100)) # Garbage
    f.write(create_record(10, 1600000000, 50))
    f.write(os.urandom(200)) # Garbage
    f.write(create_record(12, 1600000050, 20))
    f.write(os.urandom(4000)) # Padding to meet size requirement

# File 2: Invalid size (<= 4096), should be ignored
f2_path = os.path.join(base_dir, "data2.log")
with open(f2_path, "wb") as f:
    f.write(create_record(99, 1500000000, 10))
    f.write(os.urandom(100))

# File 3: Valid size, in subdir
f3_path = os.path.join(base_dir, "subdir", "data3.log")
with open(f3_path, "wb") as f:
    f.write(os.urandom(4000)) # Padding
    f.write(create_record(15, 1600000025, 100))
    f.write(create_record(10, 1600000100, 10))

# File 4: Valid size, wrong extension
f4_path = os.path.join(base_dir, "data4.dat")
with open(f4_path, "wb") as f:
    f.write(os.urandom(4100)) # Padding to ensure size > 4096
    f.write(create_record(88, 1600000010, 5))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
