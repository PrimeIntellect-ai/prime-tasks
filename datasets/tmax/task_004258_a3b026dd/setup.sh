#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/generate_data.py
import os
import struct
import random
import numpy as np
import cv2

# Generate clean files
clean_dir = "/app/corpus/clean"
for i in range(50):
    payload_len = random.randint(10, 100)
    payload = bytes([random.randint(0, 255) for _ in range(payload_len)])
    checksum = 0
    for b in payload:
        checksum ^= b

    with open(os.path.join(clean_dir, f"clean_{i}.dsf2"), "wb") as f:
        f.write(b"DSF2")
        f.write(struct.pack("<I", payload_len))
        f.write(payload)
        f.write(bytes([checksum]))

# Generate evil files
evil_dir = "/app/corpus/evil"
# Bad magic
with open(os.path.join(evil_dir, "evil_bad_magic.dsf2"), "wb") as f:
    f.write(b"DSF3")
    f.write(struct.pack("<I", 10))
    f.write(b"A" * 10)
    f.write(bytes([0]))

# Integer overflow
with open(os.path.join(evil_dir, "evil_overflow.dsf2"), "wb") as f:
    f.write(b"DSF2")
    f.write(struct.pack("<I", 0xFFFFFFFF))
    f.write(b"A" * 10)
    f.write(bytes([0]))

# Bad checksum
with open(os.path.join(evil_dir, "evil_bad_checksum.dsf2"), "wb") as f:
    payload = b"A" * 10
    f.write(b"DSF2")
    f.write(struct.pack("<I", 10))
    f.write(payload)
    f.write(bytes([255])) # wrong checksum

# Truncated
with open(os.path.join(evil_dir, "evil_truncated.dsf2"), "wb") as f:
    f.write(b"DSF2")
    f.write(struct.pack("<I", 100))
    f.write(b"A" * 10)

# Appended garbage
with open(os.path.join(evil_dir, "evil_garbage.dsf2"), "wb") as f:
    payload_len = 10
    payload = bytes([0] * payload_len)
    f.write(b"DSF2")
    f.write(struct.pack("<I", payload_len))
    f.write(payload)
    f.write(bytes([0]))
    f.write(b"GARBAGE")

# Generate video
video_path = "/app/experiment_video.mp4"
width, height = 640, 480
fps = 30
total_frames = 900
pulse_frames = random.sample(range(total_frames), 27)

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter(video_path, fourcc, fps, (width, height), isColor=False)

for i in range(total_frames):
    frame = np.zeros((height, width), dtype=np.uint8)
    if i in pulse_frames:
        frame[235:245, 315:325] = 255
    out.write(frame)

out.release()
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
