#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/dataset

    cat << 'EOF' > /home/user/dataset/config.ini
[SENSOR]
VERSION=2.1
MAGIC_BYTES=SENS
AUTHOR=RESEARCH_TEAM
EOF

    cat << 'EOF' > /home/user/dataset/files.txt
C:\dataset\alpha.dat
C:\dataset\beta.dat
C:\dataset\gamma.dat
C:\dataset\corrupt.dat
EOF

    cat << 'EOF' > /home/user/setup_bins.py
import struct
import os

def create_bin(filename, magic, sensor_id, timestamp, payload_size=50):
    filepath = os.path.join('/home/user/dataset', filename)
    with open(filepath, 'wb') as f:
        # 4 bytes magic, 4 bytes uint32, 8 bytes uint64
        header = struct.pack('<4s I Q', magic.encode('ascii'), sensor_id, timestamp)
        f.write(header)
        f.write(os.urandom(payload_size))

create_bin('alpha.dat', 'SENS', 101, 1700000000)
create_bin('beta.dat', 'SENS', 102, 1700000050)
create_bin('gamma.dat', 'SENS', 103, 1700000100)
# Corrupt magic byte file
create_bin('corrupt.dat', 'BAD!', 999, 1700000999)
EOF

    python3 /home/user/setup_bins.py
    rm /home/user/setup_bins.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
