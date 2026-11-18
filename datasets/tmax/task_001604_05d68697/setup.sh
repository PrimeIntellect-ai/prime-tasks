#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app/clean_corpus
    mkdir -p /app/evil_corpus

    python3 -c "
import os
import py_compile
import hashlib
import cv2
import numpy as np

# 1. Generate Video
# 'EXPLOIT!' -> 01000101 01011000 01010000 01001100 01001111 01001001 01010100 00100001
bits = ''.join([format(ord(c), '08b') for c in 'EXPLOIT!'])
out = cv2.VideoWriter('/app/breach_record.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100))
for bit in bits:
    color = 255 if bit == '1' else 0
    frame = np.full((100, 100, 3), color, dtype=np.uint8)
    out.write(frame)
out.release()

# 2. Generate Corpora
manifest_hashes = []

def get_hash(filepath):
    with open(filepath, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()

# Clean corpus (50 files)
for i in range(50):
    src = f'/tmp/clean_{i}.py'
    with open(src, 'w') as f:
        f.write(f'print(\"clean {i}\")\n')
    pyc = f'/app/clean_corpus/clean_{i}.pyc'
    py_compile.compile(src, cfile=pyc)
    manifest_hashes.append(get_hash(pyc))

# Evil corpus - in manifest with split payload (25 files)
for i in range(25):
    src = f'/tmp/evil_in_{i}.py'
    with open(src, 'w') as f:
        f.write(f'a = \"EXPL\"\nb = \"OIT!\"\nc = a + b\nprint(\"evil {i}\")\n')
    pyc = f'/app/evil_corpus/evil_in_{i}.pyc'
    py_compile.compile(src, cfile=pyc)
    manifest_hashes.append(get_hash(pyc))

# Evil corpus - not in manifest (25 files)
for i in range(25, 50):
    src = f'/tmp/evil_out_{i}.py'
    with open(src, 'w') as f:
        f.write(f'print(\"evil out {i}\")\n')
    pyc = f'/app/evil_corpus/evil_out_{i}.pyc'
    py_compile.compile(src, cfile=pyc)

# 3. Write Manifest
with open('/app/manifest.txt', 'w') as f:
    for h in manifest_hashes:
        f.write(f'{h}\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
