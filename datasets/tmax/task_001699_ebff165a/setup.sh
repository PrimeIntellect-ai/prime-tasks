#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/assets
    mkdir -p /app/fast-dedup-1.2.0/fast_dedup

    # Generate test data: 100 1MB files from 10 unique 100KB chunks
    cat << 'EOF' > /tmp/generate_assets.py
import os
import random
import struct

assets_dir = "/home/user/assets"
os.makedirs(assets_dir, exist_ok=True)

# 10 unique chunks of 100KB (102400 bytes)
chunks = [os.urandom(102400) for _ in range(10)]

for i in range(100):
    file_path = os.path.join(assets_dir, f"asset_{i:03d}.bin")
    with open(file_path, "wb") as f:
        # We need exactly 1MB = 1048576 bytes
        # Let's write a 16 byte header, then 10 chunks of 102400 bytes = 1024000 bytes
        # Wait, 16 + 1024000 = 1024016. We need 1048576.
        # Let's write a 16 byte header, plus 10 chunks of 104856 bytes.
        # 1048576 - 16 = 1048560 bytes. 1048560 / 10 = 104856 bytes per chunk.
        pass

EOF

    cat << 'EOF' > /tmp/generate_assets2.py
import os
import random

assets_dir = "/home/user/assets"
os.makedirs(assets_dir, exist_ok=True)

# 10 unique chunks of 104856 bytes
chunks = [os.urandom(104856) for _ in range(10)]

for i in range(100):
    file_path = os.path.join(assets_dir, f"asset_{i:03d}.bin")
    with open(file_path, "wb") as f:
        # 16 byte header
        f.write(os.urandom(16))
        # 10 chunks
        for _ in range(10):
            f.write(random.choice(chunks))
EOF
    python3 /tmp/generate_assets2.py

    # Create vendored package
    cat << 'EOF' > /app/fast-dedup-1.2.0/setup.py
from setuptools import setup, find_packages

setup(
    name='fast-dedup',
    version='1.2.0',
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/fast-dedup-1.2.0/fast_dedup/__init__.py
from .core import deduplicate_directory
EOF

    cat << 'EOF' > /app/fast-dedup-1.2.0/fast_dedup/core.py
import os
import hashlib
import json

def deduplicate_directory(input_dir, output_file):
    blocks = {}
    file_metadata = {}

    for filename in os.listdir(input_dir):
        filepath = os.path.join(input_dir, filename)
        if not os.path.isfile(filepath):
            continue

        with open(filepath, 'rb') as f:
            # Bug: struct is not imported
            header = f.read(16)
            magic = struct.unpack('<16s', header)[0]

            file_blocks = []
            while True:
                chunk = f.read(104856)
                if not chunk:
                    break
                h = hashlib.sha256(chunk).hexdigest()
                if h not in blocks:
                    blocks[h] = chunk
                file_blocks.append(h)

            file_metadata[filename] = file_blocks

    with open(output_file, 'wb') as f:
        # Write packed format
        # For simplicity, just write a json with metadata and blocks
        # We need the output to be small
        out_data = {
            'metadata': file_metadata,
            'blocks': {k: v.hex() for k, v in blocks.items()}
        }
        f.write(json.dumps(out_data).encode('utf-8'))
EOF

    cat << 'EOF' > /app/fast-dedup-1.2.0/Makefile
install:
	pithon setup.py install
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
