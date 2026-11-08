#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6
    pip3 install --default-timeout=100 pytest opencv-python-headless numpy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
import os

# Generate video
frames = [1, 0, 1, 0, 1, 0, 1, 1, 0, 0]
out = cv2.VideoWriter('/app/sync_signal.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1, (100, 100))
for bit in frames:
    color = 255 if bit == 1 else 0
    frame = np.full((100, 100, 3), color, dtype=np.uint8)
    out.write(frame)
out.release()

seed = 684

def make_payload(filename, instructions, bad_checksum=False):
    inst_str = "\n".join(instructions) + "\n"
    checksum = sum(ord(c) for c in inst_str) + seed
    if bad_checksum:
        checksum += 1
    with open(filename, 'w') as f:
        f.write(f"CHECKSUM: {checksum}\n")
        f.write(inst_str)

# Clean payloads
for i in range(10):
    make_payload(f'/app/corpus/clean/clean_{i}.txt', ["PUSH 5", "PUSH 10", "ADD", "HALT"])

# Evil payloads
make_payload('/app/corpus/evil/evil_0.txt', ["PUSH 5", "HALT"], bad_checksum=True)
make_payload('/app/corpus/evil/evil_1.txt', ["PUSH 1"] * 12 + ["HALT"]) # stack overflow
make_payload('/app/corpus/evil/evil_2.txt', ["POP", "HALT"]) # stack underflow
make_payload('/app/corpus/evil/evil_3.txt', ["JMP 0"]) # infinite loop
make_payload('/app/corpus/evil/evil_4.txt', ["JMP 5", "HALT"]) # out of bounds
make_payload('/app/corpus/evil/evil_5.txt', ["PUSH 1", "JMP -1"]) # infinite loop
for i in range(6, 10):
    make_payload(f'/app/corpus/evil/evil_{i}.txt', ["ADD", "HALT"]) # underflow
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
