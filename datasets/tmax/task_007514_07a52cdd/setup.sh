#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct

legacy_dir = "/home/user/legacy_projects"
os.makedirs(legacy_dir, exist_ok=True)
os.makedirs("/home/user/organized_projects", exist_ok=True)

def create_v1_file(path, filename, payload):
    with open(path, 'wb') as f:
        f.write(b'LEGA')
        f.write(b'\x01')
        filename_bytes = filename.encode('ascii')
        f.write(struct.pack('<H', len(filename_bytes)))
        f.write(filename_bytes)
        f.write(payload)

def create_v2_file(path, filename, payload):
    with open(path, 'wb') as f:
        f.write(b'LEGA')
        f.write(b'\x02')
        filename_bytes = filename.encode('utf-16le')
        f.write(struct.pack('<H', len(filename_bytes)))
        f.write(filename_bytes)
        f.write(payload)

# Generate test data
create_v1_file(os.path.join(legacy_dir, "file_001.dat"), "report_2020.txt", b'Report data for 2020')
create_v2_file(os.path.join(legacy_dir, "file_002.dat"), "logo_v2.png", b'\x89PNG\r\n\x1a\n\x00\x00')
create_v1_file(os.path.join(legacy_dir, "file_003.dat"), "config.ini", b'[settings]\nkey=value')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
