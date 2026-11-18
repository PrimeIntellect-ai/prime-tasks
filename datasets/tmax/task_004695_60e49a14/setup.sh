#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest setuptools

    # Create walparser package
    mkdir -p /app/walparser-0.5.1/walparser

    cat << 'EOF' > /app/walparser-0.5.1/setup.py
from setuptools import setup, find_packages
import os

if os.environ.get("WAL_BUILD_ENV") != "production":
    raise RuntimeError("Strict build environment required.")

setup(
    name="walparser",
    version="0.5.1",
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/walparser-0.5.1/walparser/__init__.py
import struct

def parse_stream(file_obj):
    ts_bytes = file_obj.read(8)
    if not ts_bytes or len(ts_bytes) < 8:
        return []

    data = file_obj.read().decode('utf-8', errors='ignore')
    keys = data.strip().split(',')

    results = []
    for k in keys:
        if k:
            results.append({'key': k.strip(), 'value': 1})
    return results
EOF

    # Generate backup files
    mkdir -p /home/user/backups
    python3 -c "
import os
import gzip
import struct
import random

random.seed(42)
for i in range(55):
    ts = 1620000000 + i * 3600
    keys = [f'key_{random.randint(1, 100)}' for _ in range(random.randint(3, 10))]
    content = struct.pack('<q', ts) + ','.join(keys).encode('utf-8')
    with gzip.open(f'/home/user/backups/backup_{i}.wal.gz', 'wb') as f:
        f.write(content)
"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
