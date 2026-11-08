#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg python3-opencv
    pip3 install pytest numpy

    mkdir -p /app/corpus/evil /app/corpus/clean

    cat << 'EOF' > /tmp/setup.py
import os
import cv2
import numpy as np

def create_mp4(filename, payload):
    bits = ''.join(f'{b:08b}' for b in payload)
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(filename, fourcc, 30.0, (10, 10))

    red_frame = np.zeros((10, 10, 3), dtype=np.uint8)
    red_frame[:] = (0, 0, 255) # BGR format

    blue_frame = np.zeros((10, 10, 3), dtype=np.uint8)
    blue_frame[:] = (255, 0, 0) # BGR format

    for bit in bits:
        if bit == '1':
            out.write(red_frame)
        else:
            out.write(blue_frame)
    out.release()

elf_header = b'\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00'

payload1 = elf_header + b'POST /upload?path=../../../../etc/shadow HTTP/1.1'
payload1 += b'\x00' * (300 - len(payload1))

create_mp4('/app/suspicious_upload.mp4', payload1)
create_mp4('/app/corpus/evil/evil1.mp4', elf_header + b'../../../../etc/passwd')
create_mp4('/app/corpus/evil/evil2.mp4', elf_header + b'cat /etc/shadow')
create_mp4('/app/corpus/clean/clean1.mp4', elf_header + b'Hello World')
create_mp4('/app/corpus/clean/clean2.mp4', elf_header + b'Just a normal file')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
