#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        golang-go \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate the specs image
    convert -size 800x400 xc:white -font DejaVu-Sans -pointsize 16 -fill black -annotate +20+40 "CUSTOM LOG FORMAT SPECS\n1. Magic Header: exactly 5 bytes [0x4B, 0x41, 0x5A, 0x4F, 0x4F]\n2. Payload: standard DEFLATE compression (no gzip/zlib wrappers)\n3. Integrity: 4-byte CRC32 (IEEE) checksum of the UNCOMPRESSED data appended as the last 4 bytes of the file (Big Endian).\n4. Malicious Flag: If uncompressed log contains the exact string 'DROP_TABLE', reject it." /app/specs.png

    # Generate the corpora using Python
    cat << 'EOF' > /tmp/gen_corpus.py
import os
import zlib
import struct
import random
import string

def random_string(length=100):
    return ''.join(random.choices(string.ascii_letters + string.digits + " \n", k=length))

def make_file(text, corrupt_magic=False, truncate_deflate=False, corrupt_crc=False):
    magic = b'\x4B\x41\x5A\x4F\x4F'
    if corrupt_magic:
        magic = b'\x00\x00\x00\x00\x00'

    text_bytes = text.encode('utf-8')
    crc = zlib.crc32(text_bytes) & 0xffffffff

    # Raw DEFLATE (wbits=-15)
    deflate_obj = zlib.compressobj(wbits=-zlib.MAX_WBITS)
    deflated = deflate_obj.compress(text_bytes) + deflate_obj.flush()

    if truncate_deflate:
        deflated = deflated[:len(deflated)//2]

    if corrupt_crc:
        crc = (crc + 1) & 0xffffffff

    trailer = struct.pack('>I', crc)

    return magic + deflated + trailer

for i in range(50):
    with open(f'/app/corpus/clean/clean_{i}.bin', 'wb') as f:
        f.write(make_file(random_string()))

for i in range(10):
    with open(f'/app/corpus/evil/evil_magic_{i}.bin', 'wb') as f:
        f.write(make_file(random_string(), corrupt_magic=True))

for i in range(15):
    with open(f'/app/corpus/evil/evil_trunc_{i}.bin', 'wb') as f:
        f.write(make_file(random_string(), truncate_deflate=True))

for i in range(15):
    with open(f'/app/corpus/evil/evil_crc_{i}.bin', 'wb') as f:
        f.write(make_file(random_string(), corrupt_crc=True))

for i in range(10):
    with open(f'/app/corpus/evil/evil_drop_{i}.bin', 'wb') as f:
        f.write(make_file(random_string() + "DROP_TABLE" + random_string()))
EOF
    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
