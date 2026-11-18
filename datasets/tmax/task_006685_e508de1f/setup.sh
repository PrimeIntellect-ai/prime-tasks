#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user

    python3 -c '
import struct

text = "G1 X10 Y10 E1.50\nG0 X20 Y20\nG1 E0.50\nG1 X15 Y15 E2.25\n"
rle = []
i = 0
while i < len(text):
    count = 1
    while i + count < len(text) and text[i + count] == text[i] and count < 255:
        count += 1
    rle.append(struct.pack("B", count))
    rle.append(text[i].encode("ascii"))
    i += count

with open("/home/user/docs_archive.bin", "wb") as f:
    for b in rle:
        f.write(b)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
