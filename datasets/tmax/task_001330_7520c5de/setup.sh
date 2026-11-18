#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++ gawk
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

np.random.seed(42)
p01 = 0.15
p10 = 0.25
frames = 500
fps = 10

states = [0]
for _ in range(1, frames):
    if states[-1] == 0:
        states.append(1 if np.random.rand() < p01 else 0)
    else:
        states.append(0 if np.random.rand() < p10 else 1)

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/spectroscopy_feed.mp4', fourcc, fps, (64, 64), False)

for s in states:
    frame = np.random.normal(20, 5, (64, 64))
    center = np.random.normal(50 if s == 0 else 200, 10, (16, 16))
    frame[24:40, 24:40] = center
    frame = np.clip(frame, 0, 255).astype(np.uint8)
    out.write(frame)

out.release()
EOF

    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
