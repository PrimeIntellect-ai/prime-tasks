#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import struct
import json
import os

os.makedirs("/home/user/artifacts", exist_ok=True)

json_data = {
    "repository": "core-binaries",
    "backup_version": 1,
    "artifacts": [
        {"id": "glibc-2.38", "sha256_checksum": "a1b2c3d4e5f60789"},
        {"id": "linux-kernel-6.5-rc1", "sha256_checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
        {"id": "gcc-13.2", "sha256_checksum": "ffeeddccbbaa9988"}
    ]
}

payload_bytes = json.dumps(json_data).encode("utf-8")

chunk_size = 32
chunks = []
for i in range(0, len(payload_bytes), chunk_size):
    chunks.append(payload_bytes[i:i+chunk_size])

def create_chunk(chunk_id, data):
    magic = b"CHNK"
    c_id = struct.pack("<I", chunk_id)
    c_len = struct.pack("<I", len(data))
    return magic + c_id + c_len + data

sequence = []
for idx, data in enumerate(chunks):
    sequence.append(create_chunk(idx, data))

for idx in range(2, len(chunks)):
    sequence.append(create_chunk(idx, chunks[idx]))
for idx in range(0, 4):
    if idx < len(chunks):
        sequence.append(create_chunk(idx, chunks[idx]))

with open("/home/user/artifacts/corrupted_backup.bin", "wb") as f:
    for chunk in sequence:
        f.write(chunk)
'

    chmod -R 777 /home/user
