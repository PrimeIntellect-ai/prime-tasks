#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/assets

    cat << 'EOF' > /tmp/setup_assets.py
import struct
import random
import os

random.seed(42)
valid_magic = 0xDEADBEEF
invalid_magic = 0xBAADF00D

expected_entries = []

for i in range(100):
    is_valid = i % 2 == 0
    magic = valid_magic if is_valid else invalid_magic
    proj_id = random.randint(1000, 9999)
    timestamp = random.randint(1600000000, 1700000000)

    if is_valid:
        expected_entries.append((proj_id, timestamp))

    with open(f"/home/user/assets/asset_{i:03d}.bin", "wb") as f:
        # write 16 bytes header
        f.write(struct.pack("<IIQ", magic, proj_id, timestamp))
        # write some random payload
        f.write(random.randbytes(32))

# Save expected ground truth output to a hidden location for verification
expected_entries.sort(key=lambda x: x[0])
with open("/home/user/.expected_inventory.log", "w") as f:
    for proj_id, ts in expected_entries:
        f.write(f"ProjectID: {proj_id}, Timestamp: {ts}\n")
EOF

    python3 /tmp/setup_assets.py
    rm /tmp/setup_assets.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
