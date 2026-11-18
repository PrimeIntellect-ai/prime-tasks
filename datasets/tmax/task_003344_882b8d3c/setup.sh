#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/artifacts/raw
    mkdir -p /home/user/artifacts/chunked
    mkdir -p /home/user/artifacts/restored

    cat << 'EOF' > /home/user/setup_artifacts.py
import os
import hashlib

raw_dir = "/home/user/artifacts/raw"

files = {
    "app_v1.bin": (12 * 1024 * 1024, "seed_v1"),
    "app_v2.bin": (7 * 1024 * 1024, "seed_v2"),
    "app_v3.bin": (25 * 1024 * 1024, "seed_v3")
}

for name, (size, seed) in files.items():
    path = os.path.join(raw_dir, name)
    with open(path, 'wb') as f:
        # Generate deterministic pseudo-random bytes
        for i in range(size // 1024):
            f.write(hashlib.md5(f"{seed}{i}".encode()).digest() * 64)

EOF
    python3 /home/user/setup_artifacts.py

    cat << 'EOF' > /home/user/artifacts/legacy_manifest.txt
Artifact: legacy_app.bin | Hash: 3b9c6f932e6a9f5d | Date: 2021-04-12
Artifact: driver_pack.bin | Hash: 8f4e2d1a0b9c8d7e | Date: 2021-08-22
Artifact: old_firmware.bin | Hash: 1a2b3c4d5e6f7g8h | Date: 2022-01-05
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
