#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libglib2.0-0 ffmpeg
    pip3 install pytest numpy==1.26.4 opencv-python-headless scipy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/gen_videos.py
import cv2
import numpy as np
import random
import os

def create_video(path, frames, fps=30, size=(100, 100)):
    out = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*'mp4v'), fps, size, False)
    for f in frames:
        img = np.zeros(size, dtype=np.uint8)
        if f:
            img[25:75, 25:75] = 255
        out.write(img)
    out.release()

# Clean: 10Hz -> 1 frame on, 2 frames off
clean_frames = [1 if i % 3 == 0 else 0 for i in range(300)]
for i in range(3):
    create_video(f'/app/corpus/clean/clean_{i}.mp4', clean_frames)

# Evil: random intervals
for i in range(3):
    evil_frames = []
    while len(evil_frames) < 300:
        evil_frames.append(1)
        delay = random.randint(2, 6)
        evil_frames.extend([0]*delay)
    evil_frames = evil_frames[:300]
    create_video(f'/app/corpus/evil/evil_{i}.mp4', evil_frames)

# Fixture
create_video('/app/test_fixture.mp4', evil_frames)
EOF

    python3 /tmp/gen_videos.py
    rm /tmp/gen_videos.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
