#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/clean_corpus
    mkdir -p /app/evil_corpus
    touch /app/reference_video.mp4

    cat << 'EOF' > /tmp/generate_data.py
import os
import struct
import random

def write_frm1(path, magic=b'FRM1', orig_size=6220800, comp_size=None, rle_data=b''):
    if comp_size is None:
        comp_size = len(rle_data)
    with open(path, 'wb') as f:
        f.write(magic)
        f.write(struct.pack('<Q', orig_size))
        f.write(struct.pack('<Q', comp_size))
        f.write(rle_data)

def make_valid_rle(val, total_size=6220800):
    data = bytearray()
    rem = total_size
    while rem > 0:
        c = min(255, rem)
        data.append(c)
        data.append(val)
        rem -= c
    return bytes(data)

# Clean corpus
unique_rles = [make_valid_rle(i) for i in range(40)]
for i in range(100):
    rle = unique_rles[i % 40]
    write_frm1(f'/app/clean_corpus/frame_{i:03d}.frm1', rle_data=rle)

# Evil corpus
evil_idx = 0
def get_evil_path():
    global evil_idx
    p = f'/app/evil_corpus/evil_{evil_idx:03d}.frm1'
    evil_idx += 1
    return p

# 5 incorrect magic
for _ in range(5):
    write_frm1(get_evil_path(), magic=b'BAD1', rle_data=make_valid_rle(0))

# 5 original size != 6220800
for _ in range(5):
    write_frm1(get_evil_path(), orig_size=1000, rle_data=make_valid_rle(0))

# 5 compressed size != actual
for _ in range(5):
    write_frm1(get_evil_path(), comp_size=9999, rle_data=make_valid_rle(0))

# 5 count == 0
for _ in range(5):
    rle = bytearray(make_valid_rle(0))
    rle[0] = 0 # invalid count
    write_frm1(get_evil_path(), rle_data=bytes(rle))

# 5 decompresses to < 6220800
for _ in range(5):
    write_frm1(get_evil_path(), rle_data=make_valid_rle(0, total_size=6220000))

# 5 decompresses to > 6220800
for _ in range(5):
    write_frm1(get_evil_path(), rle_data=make_valid_rle(0, total_size=6221000))

EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
