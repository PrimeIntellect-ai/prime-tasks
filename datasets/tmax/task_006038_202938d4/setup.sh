#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nasm binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import json
import base64
import zlib

os.makedirs('/home/user/packages', exist_ok=True)

packages = [
    {"name": "root", "version": "1.0.0", "dependencies": {"A": ">=1.0.0"}},
    {"name": "A", "version": "1.0.0", "dependencies": {"B": ">=1.0.0"}},
    {"name": "A", "version": "1.5.0", "dependencies": {"B": ">=2.0.0"}},
    {"name": "B", "version": "1.0.0", "dependencies": {"C": ">=1.0.0"}},
    {"name": "B", "version": "2.5.0", "dependencies": {"C": ">=1.0.0"}},
    {"name": "C", "version": "1.1.0", "dependencies": {"A": ">=1.0.0"}},
    {"name": "D", "version": "2.0.0", "dependencies": {}} # decoy
]

for i, pkg in enumerate(packages):
    json_str = json.dumps(pkg).encode('utf-8')
    compressed = zlib.compress(json_str)
    encoded = base64.b64encode(compressed).decode('utf-8')
    with open(f'/home/user/packages/pkg_{i}.dat', 'w') as f:
        f.write(encoded)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
