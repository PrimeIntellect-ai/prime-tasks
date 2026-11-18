#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app/corpus/clean /app/corpus/evil
    mkdir -p /tmp/video_frames

    cat << 'EOF' > /tmp/generate_data.py
import cv2
import numpy as np
import os

# Clean corpus
for i in range(20):
    img = np.random.randint(50, 200, (100, 100), dtype=np.uint8)
    cv2.imwrite(f"/app/corpus/clean/clean_{i:02d}.pgm", img)

# Evil corpus
for i in range(20):
    img = np.random.randint(50, 200, (100, 100), dtype=np.uint8)
    img[20:70, 20:70] = 0
    cv2.imwrite(f"/app/corpus/evil/evil_{i:02d}.pgm", img)

# Video frames
for i in range(60):
    img = np.random.randint(50, 200, (100, 100), dtype=np.uint8)
    if i >= 45: # 15 corrupted frames
        img[20:70, 20:70] = 0
    cv2.imwrite(f"/tmp/video_frames/frame_{i:04d}.png", img)
EOF

    python3 /tmp/generate_data.py
    ffmpeg -framerate 1 -i /tmp/video_frames/frame_%04d.png -c:v libx264 -pix_fmt yuv420p /app/droplet_experiment.mp4

    rm -rf /tmp/video_frames /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
