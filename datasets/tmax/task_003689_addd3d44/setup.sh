#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cargo rustc curl
    pip3 install pytest

    mkdir -p /app

    # Generate video with text at frame 73
    ffmpeg -f lavfi -i color=c=black:s=640x480:r=30:d=5 -vf "drawtext=text='PARAMS\: CHUNK=64, ALGO=ADLER32':fontcolor=white:fontsize=24:x=(w-tw)/2:y=(h-th)/2:enable='eq(n\,73)'" -c:v libx264 /app/rotation_capture.mp4

    # Create oracle
    cat << 'EOF' > /app/oracle_archiver
#!/usr/bin/env python3
import sys
import struct
import zlib

def compute_adler32(data):
    return zlib.adler32(data) & 0xffffffff

def oracle():
    data = sys.stdin.buffer.read()
    sys.stdout.buffer.write(b"ARTM")

    chunk_size = 64
    chunks = [data[i:i+chunk_size] for i in range(0, len(data), chunk_size)]

    for i, chunk in enumerate(chunks):
        sys.stdout.buffer.write(struct.pack("<H", i))
        sys.stdout.buffer.write(struct.pack("<H", len(chunk)))
        sys.stdout.buffer.write(struct.pack("<I", compute_adler32(chunk)))
        sys.stdout.buffer.write(chunk)

    sys.stdout.buffer.write(b"ENDM")
    sys.stdout.buffer.write(struct.pack("<I", len(data)))

if __name__ == "__main__":
    oracle()
EOF
    chmod +x /app/oracle_archiver

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
