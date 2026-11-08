#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/archives
    mkdir -p /home/user/extracted

    cat << 'EOF' > /home/user/setup_archives.py
import struct
import os

def rle_compress(data):
    compressed = bytearray()
    i = 0
    while i < len(data):
        count = 1
        while i + count < len(data) and data[i+count] == data[i] and count < 255:
            count += 1
        compressed.append(count)
        compressed.append(data[i])
        i += count
    return compressed

def create_archive(filepath, filename, iso_text):
    data = iso_text.encode('iso-8859-1')
    compressed = rle_compress(data)

    with open(filepath, 'wb') as f:
        f.write(b'BKP1')
        f.write(struct.pack('B', len(filename)))
        f.write(filename.encode('ascii'))
        f.write(struct.pack('<I', len(data)))
        f.write(struct.pack('<I', len(compressed)))
        f.write(struct.pack('B', 2)) # Encoding flag
        f.write(compressed)

os.makedirs('/home/user/archives', exist_ok=True)

# File 1: Simple English with repeating characters
text1 = "AAAAABBBBBCCCCCDDDDD"
create_archive('/home/user/archives/test1.bkp', 'test1.txt', text1)

# File 2: Text with ISO-8859-1 characters (e.g., é, ñ, ü)
text2 = "Café au lait and piña coladas are müy bien! " * 5
create_archive('/home/user/archives/test2.bkp', 'test2.txt', text2)

# File 3: Large repetitive ISO-8859-1
text3 = "ñ" * 100 + "A" * 50 + "é" * 100
create_archive('/home/user/archives/test3.bkp', 'test3.txt', text3)

EOF

    python3 /home/user/setup_archives.py
    rm /home/user/setup_archives.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
