#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_dataset
    mkdir -p /home/user/organized_dataset

    cat << 'EOF' > /tmp/setup_data.py
import struct
import os

records = [
    ("file_A.dat", b"SENS0001", 1690000000),
    ("file_B.dat", b"SENS0002", 1690000050),
    ("file_C.dat", b"SENS0001", 1690000100),
    ("file_D.dat", b"SENS0003", 1690000150),
    ("file_E.dat", b"SENS0002", 1690000200),
]

for filename, sensor_id, timestamp in records:
    filepath = os.path.join("/home/user/raw_dataset", filename)
    with open(filepath, "wb") as f:
        # Magic string
        f.write(b"SNSR_DAT")
        # Sensor ID padded to 8 bytes
        f.write(sensor_id.ljust(8, b'\x00'))
        # Timestamp (unsigned long long, little endian)
        f.write(struct.pack("<Q", timestamp))
        # Write some padding to simulate a larger file (1MB)
        f.seek(1024 * 1024 - 1)
        f.write(b'\x00')
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
