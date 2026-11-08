#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data
    cd /home/user/data

    cat << 'EOF' > generate_dump.py
import gzip
import os

# Create a 5000 byte empty file filled with random hex (not 1F 8B)
import random
random.seed(42)

def random_bytes(n):
    return bytes([random.choice([b for b in range(256) if b not in (0x1F, 0x8B)]) for _ in range(n)])

data = bytearray(random_bytes(5000))

# Valid gzip 1
msg1 = b"System config ok."
gz1 = gzip.compress(msg1)
data[100:100+len(gz1)] = gz1

# Invalid gzip 2 (has magic bytes, but corrupted payload)
msg2 = b"Corrupted data stream..."
gz2 = bytearray(gzip.compress(msg2))
gz2[15] ^= 0xFF # corrupt a byte in the compressed payload
data[500:500+len(gz2)] = gz2

# Valid gzip 3
msg3 = b"Database backup complete."
gz3 = gzip.compress(msg3)
data[1000:1000+len(gz3)] = gz3

# Valid gzip 4
msg4 = b"User data intact."
gz4 = gzip.compress(msg4)
data[2000:2000+len(gz4)] = gz4

with open("mixed_backups.bin", "wb") as f:
    f.write(data)
EOF

    python3 generate_dump.py
    rm generate_dump.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
