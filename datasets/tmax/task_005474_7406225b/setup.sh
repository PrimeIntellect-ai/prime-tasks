#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/repo
    mkdir -p /home/user/out_files

    cat << 'EOF' > /home/user/setup_repo.py
import struct
import os

def write_part(filename, entries):
    with open(filename, 'wb') as f:
        f.write(b'ART\0')
        for entry in entries:
            f.write(struct.pack('<B', entry['type']))
            path = entry['path'].encode('utf-8')
            f.write(struct.pack('<H', len(path)))
            f.write(path)

            if entry['type'] == 0:
                f.write(struct.pack('<I', entry['offset']))
                data = bytearray(entry['data'])
                # XOR encode
                for i in range(len(data)):
                    data[i] ^= 0xAA
                f.write(struct.pack('<I', len(data)))
                f.write(data)
            elif entry['type'] == 1:
                target = entry['target'].encode('utf-8')
                f.write(struct.pack('<H', len(target)))
                f.write(target)

# File chunks
# file1.txt: "Hello World! This is a test." (28 bytes)
chunk1 = b"Hello World! " # 13 bytes, offset 0
chunk2 = b"This is a test." # 15 bytes, offset 13

write_part('/home/user/repo/part1.part', [
    {'type': 0, 'path': 'file1.txt', 'offset': 0, 'data': chunk1},
    {'type': 1, 'path': 'linkA', 'target': 'linkB'}
])

write_part('/home/user/repo/part2.part', [
    {'type': 0, 'path': 'file1.txt', 'offset': 13, 'data': chunk2},
    {'type': 1, 'path': 'linkB', 'target': 'linkC'}
])

write_part('/home/user/repo/part3.part', [
    {'type': 1, 'path': 'linkC', 'target': 'linkA'}, # Cycle! A->B->C->A
    {'type': 1, 'path': 'valid_link', 'target': 'file1.txt'}
])

EOF

    python3 /home/user/setup_repo.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
