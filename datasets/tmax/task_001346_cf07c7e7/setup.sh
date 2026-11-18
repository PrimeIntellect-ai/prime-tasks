#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang ffmpeg espeak
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate audio memo
    espeak -w /app/reference_memo.wav "The new system compression XOR key is forty two"

    # Generate corpora
    python3 -c "
import os
import gzip

def xor_bytes(data, key=42):
    return bytes([b ^ key for b in data])

def generate_file(path, magic, log):
    header = magic + os.urandom(60)
    log_bytes = log.encode('utf-8') + b'\n---END_LOG---\n'
    data = os.urandom(100)

    payload = header + log_bytes + data
    gzipped = gzip.compress(payload)
    xored = xor_bytes(gzipped, 42)

    with open(path, 'wb') as f:
        f.write(xored)

# Clean
for i in range(10):
    generate_file(f'/app/corpora/clean/file_{i}.bin', b'\x00\x11\x22\x33', 'AUTHORIZATION: VALID\nDATE: 2023-10-01')

# Evil
for i in range(5):
    generate_file(f'/app/corpora/evil/file_{i}_magic.bin', b'\xDE\xAD\xBE\xEF', 'AUTHORIZATION: VALID\nDATE: 2023-10-01')

for i in range(5, 10):
    generate_file(f'/app/corpora/evil/file_{i}_log.bin', b'\x00\x11\x22\x33', 'AUTHORIZATION: BYPASS\nDATE: 2023-10-01')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
