#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import json
import hashlib

os.makedirs('/home/user/raw_chunks', exist_ok=True)

artifacts_data = [
    {
        "name": "app_release_linux_amd64.tar.gz",
        "chunks": [b"chunk1_data_aaaaa", b"chunk2_data_bbbbb", b"chunk3_data_ccccc"],
        "corrupt": False
    },
    {
        "name": "database_schema.sqlite",
        "chunks": [b"db_part1_11111", b"db_part2_22222"],
        "corrupt": False
    },
    {
        "name": "legacy_drivers.zip",
        "chunks": [b"zip_partA", b"zip_partB", b"zip_partC"],
        "corrupt": True
    }
]

manifest = {"artifacts": []}
chunk_idx = 0

for art in artifacts_data:
    merged_data = b"".join(art["chunks"])
    real_sha256 = hashlib.sha256(merged_data).hexdigest()

    chunk_names = []
    for chunk_data in art["chunks"]:
        chunk_name = f"scrambled_xyz_{chunk_idx}.dat"
        chunk_names.append(chunk_name)

        write_data = chunk_data
        if art["corrupt"] and chunk_idx == len(chunk_names) - 1:
            write_data = chunk_data + b"corrupted_bytes"

        with open(f"/home/user/raw_chunks/{chunk_name}", "wb") as f:
            f.write(write_data)

        chunk_idx += 1

    manifest["artifacts"].append({
        "canonical_name": art["name"],
        "chunks": chunk_names,
        "expected_sha256": real_sha256
    })

with open('/home/user/manifest.json', 'w') as f:
    json.dump(manifest, f, indent=4)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
