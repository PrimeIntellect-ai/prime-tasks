#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc zlib1g-dev libjson-c-dev
    pip3 install pytest

    # Generate reference video
    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=1:size=320x240:rate=10 -c:v libx264 /app/experiment_video.mp4

    # Generate WAL dataset
    cat << 'EOF' > /tmp/gen_wal.py
import struct
import zlib
import json
import os

def create_wal(path, magic, json_str, payload, compress=True):
    with open(path, 'wb') as f:
        f.write(magic)
        f.write(struct.pack('<I', len(json_str)))
        f.write(json_str.encode('utf-8'))
        if compress:
            f.write(zlib.compress(payload))
        else:
            f.write(payload)

os.makedirs('/dataset', exist_ok=True)
os.makedirs('/test_corpus/clean', exist_ok=True)
os.makedirs('/test_corpus/evil', exist_ok=True)

# Clean WAL
create_wal('/dataset/clean1.wal', b'WAL\x00', '{"checksum": "123"}', b'data123')
create_wal('/test_corpus/clean/test_clean1.wal', b'WAL\x00', '{"checksum": "abc"}', b'payload_clean')

# Evil WALs
create_wal('/dataset/evil1.wal', b'MAL\x00', '{"checksum": "123"}', b'data123') # bad magic
create_wal('/dataset/evil2.wal', b'WAL\x00', '{"check', b'data123') # truncated JSON
create_wal('/dataset/evil3.wal', b'WAL\x00', '{"checksum": "123"}', b'bad_zlib_data', compress=False) # bad zlib

create_wal('/test_corpus/evil/test_evil1.wal', b'BAD\x00', '{"checksum": "123"}', b'data')
EOF
    python3 /tmp/gen_wal.py
    rm /tmp/gen_wal.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
