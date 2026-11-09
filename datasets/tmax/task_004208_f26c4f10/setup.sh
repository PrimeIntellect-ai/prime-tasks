#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        ffmpeg

    pip3 install pytest Pillow

    mkdir -p /app

    # Create the oracle
    cat << 'EOF' > /app/oracle
#!/usr/bin/env python3
import sys
import struct
import zlib

def check_wal(path):
    BAV_EXPECTED = 17
    try:
        with open(path, 'rb') as f:
            data = f.read()
    except Exception:
        print("CORRUPT")
        return

    if len(data) < 6:
        print("INVALID_HEADER")
        return

    magic = data[0:3]
    version = data[3]
    bav = struct.unpack('<H', data[4:6])[0]

    if magic != b'WAL' or version != 1:
        print("INVALID_HEADER")
        return
    if bav != BAV_EXPECTED:
        print("INVALID_BAV")
        return

    offset = 6
    while offset < len(data):
        if offset + 4 > len(data):
            print("CORRUPT")
            return
        L = struct.unpack('<I', data[offset:offset+4])[0]
        offset += 4

        if offset + L > len(data):
            print("CORRUPT")
            return
        payload = data[offset:offset+L]
        offset += L

        if offset + 4 > len(data):
            print("CORRUPT")
            return
        stored_crc = struct.unpack('<I', data[offset:offset+4])[0]
        offset += 4

        computed_crc = zlib.crc32(payload) & 0xFFFFFFFF
        if stored_crc != computed_crc:
            print("CORRUPT")
            return

    print("SAFE")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(1)
    check_wal(sys.argv[1])
EOF
    chmod +x /app/oracle

    # Generate the alert video
    cat << 'EOF' > /tmp/gen_video.py
import os
from PIL import Image
import subprocess

os.makedirs('/tmp/frames', exist_ok=True)
for i in range(150):
    color = (255, 255, 255) if i < 17 else (0, 0, 0)
    img = Image.new('RGB', (64, 64), color)
    img.save(f'/tmp/frames/frame_{i:03d}.png')

subprocess.run([
    'ffmpeg', '-y', '-framerate', '30',
    '-i', '/tmp/frames/frame_%03d.png',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
    '/app/alert.mp4'
], check=True)
EOF
    python3 /tmp/gen_video.py
    rm -rf /tmp/frames /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
