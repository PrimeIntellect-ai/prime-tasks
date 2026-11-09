#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil
    ffmpeg -f lavfi -i testsrc=duration=4:size=320x240:rate=30 -c:v libx264 -pix_fmt yuv420p /app/test_sequence.mp4

    cat << 'EOF' > /tmp/gen_corpus.py
import binascii
import os

def write_patch(path, frame, diff, tamper_crc=False, tamper_diff=False):
    payload = f"{diff}"
    if tamper_diff:
        payload = "++ tampered\n" + payload

    crc = binascii.crc32(payload.encode('utf-8')) & 0xFFFFFFFF
    if tamper_crc:
        crc = (crc + 1) & 0xFFFFFFFF

    with open(path, 'w') as f:
        f.write(f"FRAME {frame}\n")
        f.write(f"CRC32 {crc:08x}\n")
        f.write(payload)

# Clean corpus
write_patch('/app/corpus/clean/patch1.txt', 50, "@@ -1,2 +1,2 @@\n+metadata")
write_patch('/app/corpus/clean/patch2.txt', 0, "@@ -5 +6 @@\n+more data")
write_patch('/app/corpus/clean/patch3.txt', 119, "@@ start @@\n-delete")

# Evil corpus
# 1. Out of bounds frame
write_patch('/app/corpus/evil/evil1.txt', 120, "@@ -1,2 +1,2 @@\n+metadata")
write_patch('/app/corpus/evil/evil2.txt', -1, "@@ -1,2 +1,2 @@\n+metadata")
# 2. Bad CRC
write_patch('/app/corpus/evil/evil3.txt', 10, "@@ -1,2 +1,2 @@\n+metadata", tamper_crc=True)
# 3. Bad Diff header
write_patch('/app/corpus/evil/evil4.txt', 15, "@@ -1,2 +1,2 @@\n+metadata", tamper_diff=True)
EOF
    python3 /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
