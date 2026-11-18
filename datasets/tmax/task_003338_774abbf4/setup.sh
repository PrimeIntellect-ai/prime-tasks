#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-opencv python3-numpy ffmpeg gcc
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np
import random

frames = 300
red_frames = 73
width, height = 320, 240

out = cv2.VideoWriter('/app/monitoring_feed.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (width, height))

red_indices = set(random.sample(range(frames), red_frames))

for i in range(frames):
    img = np.zeros((height, width, 3), dtype=np.uint8)
    if i in red_indices:
        img[0:16, 0:16] = [0, 0, 255] # BGR format
    out.write(img)

out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
