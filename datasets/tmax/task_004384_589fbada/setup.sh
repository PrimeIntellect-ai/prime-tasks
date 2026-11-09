#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import json
import zlib
import struct
import random

repo_dir = '/home/user/artifact_repo'
os.makedirs(repo_dir, exist_ok=True)

# Generate a list of random floats
random.seed(42)
floats = [random.uniform(-1000.0, 1000.0) for _ in range(50000)]
# Insert a specific maximum value
expected_max = 8456.123456
floats.insert(random.randint(0, len(floats)), expected_max)

# Pack into 32-bit little-endian floats
binary_data = struct.pack(f'<{len(floats)}f', *floats)

# Compress using zlib
compressed_data = zlib.compress(binary_data)

# XOR with 0x42
xored_data = bytes([b ^ 0x42 for b in compressed_data])

# Split into 3 chunks
chunk_size = len(xored_data) // 3
chunks = [
    xored_data[:chunk_size],
    xored_data[chunk_size:2*chunk_size],
    xored_data[2*chunk_size:]
]

chunk_names = ["alpha.chk", "beta.chk", "gamma.chk"]

for name, data in zip(chunk_names, chunks):
    with open(os.path.join(repo_dir, name), 'wb') as f:
        f.write(data)

# Create manifest
manifest = {
    "repository_version": "1.0",
    "artifacts": [
        {
            "id": "model_weights_v1",
            "chunks": ["old1.chk", "old2.chk"]
        },
        {
            "id": "model_weights_v2",
            "chunks": chunk_names,
            "description": "Latest weights"
        }
    ]
}

with open(os.path.join(repo_dir, 'manifest.json'), 'w') as f:
    json.dump(manifest, f, indent=4)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
