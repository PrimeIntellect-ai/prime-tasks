#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip gcc
    pip3 install pytest

    mkdir -p /home/user/setup_tmp/part1
    mkdir -p /home/user/setup_tmp/part2

    # Helper function to generate RLE + shift +5
    generate_rle() {
        local text="$1"
        local out="$2"
        python3 -c "
import sys
text = '$text'
out_bytes = bytearray()
if not text:
    sys.exit(0)
curr_char = text[0]
count = 1
for char in text[1:]:
    if char == curr_char and count < 255:
        count += 1
    else:
        out_bytes.append(count)
        out_bytes.append((ord(curr_char) + 5) % 256)
        curr_char = char
        count = 1
out_bytes.append(count)
out_bytes.append((ord(curr_char) + 5) % 256)
with open('$out', 'wb') as f:
    f.write(out_bytes)
"
    }

    # Generate files
    generate_rle "Welcome to the system documentation.\n" "/home/user/setup_tmp/part1/DOC_001_OLD.txt.rle"
    generate_rle "Chapter 1: Installation involves extracting files.\n" "/home/user/setup_tmp/part1/DOC_002_OLD.txt.rle"
    generate_rle "Chapter 2: Configuration requires setting environment variables.\n" "/home/user/setup_tmp/part2/DOC_003_OLD.txt.rle"

    # Create nested archives
    cd /home/user/setup_tmp/part1
    zip -q ../part1.zip DOC_001_OLD.txt.rle DOC_002_OLD.txt.rle
    cd /home/user/setup_tmp/part2
    zip -q ../part2.zip DOC_003_OLD.txt.rle

    cd /home/user/setup_tmp
    tar -czf /home/user/docs_archive.tar.gz part1.zip part2.zip

    # Cleanup
    rm -rf /home/user/setup_tmp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
