#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core build-essential
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate corpora
    python3 -c "
import os
import random

evil_signatures = [
    b'\x90\x90\x90\x90',
    b'\x45\x56\x41\x53\x49\x4f\x4e',
    b'\x00\x00\x00\x00'
]

for i in range(50):
    clean_data = bytearray(os.urandom(256))
    # Ensure clean data doesn't accidentally contain signatures
    for sig in evil_signatures:
        while sig in clean_data:
            clean_data = bytearray(os.urandom(256))
    with open(f'/app/corpus/clean/payload_{i}.bin', 'wb') as f:
        f.write(clean_data)

    evil_data = bytearray(os.urandom(256))
    sig = random.choice(evil_signatures)
    pos = random.randint(0, len(evil_data) - len(sig))
    evil_data[pos:pos+len(sig)] = sig
    with open(f'/app/corpus/evil/payload_{i}.bin', 'wb') as f:
        f.write(evil_data)
"

    # Generate video
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=10 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='7a4b9c2f8d1e5a6b3c9f4d7e2a1b8c5f':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,4.9,5.1)'" -c:v libx264 /app/surveillance.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
