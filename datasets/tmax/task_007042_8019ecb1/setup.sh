#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make tar
    pip3 install pytest

    mkdir -p /home/user

    # Create the setup script
    cat << 'EOF' > /tmp/setup.py
import struct
import tarfile
import os

os.makedirs('/home/user/raw_data_tmp', exist_ok=True)

# Define deterministic data for 5 files
# Format: list of (id, value)
datasets = [
    [(10, 15.234), (2, -5.1), (35, 0.0), (8, 42.119)],
    [(1, 100.001), (50, -10.0), (12, 3.14159)],
    [(99, 0.00), (3, 7.777), (7, -0.01)],
    [(105, 88.88), (4, 1.23), (11, -9.99)],
    [(22, 5.55), (6, 0.0), (25, 12.34)]
]

for i, data in enumerate(datasets, 1):
    filepath = f'/home/user/raw_data_tmp/sensor_{i}.bin'
    with open(filepath, 'wb') as f:
        for record_id, value in data:
            f.write(struct.pack('<if', record_id, value))

with tarfile.open('/home/user/raw_sensors.tar.gz', 'w:gz') as tar:
    for i in range(1, 6):
        tar.add(f'/home/user/raw_data_tmp/sensor_{i}.bin', arcname=f'sensor_{i}.bin')

# Cleanup
for i in range(1, 6):
    os.remove(f'/home/user/raw_data_tmp/sensor_{i}.bin')
os.rmdir('/home/user/raw_data_tmp')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
