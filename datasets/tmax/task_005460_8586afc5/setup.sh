#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy scipy opencv-python-headless

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
import cv2

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

# 1. Generate reference video
frame_width, frame_height = 100, 100
out = cv2.VideoWriter('/app/reference_simulation.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (frame_width, frame_height), False)
base_dist = np.random.normal(128, 20, 10000)
for i in range(20):
    # Slight shift for stable video (Wasserstein dist ~ 4.25)
    dist = base_dist + (i * 4.25)
    hist, _ = np.histogram(dist, bins=256, range=(0, 256))
    frame = np.clip(dist.reshape((100, 100)), 0, 255).astype(np.uint8)
    out.write(frame)
out.release()

# 2. Generate clean corpus
np.random.seed(42)
for i in range(20):
    with open(f'/app/corpus/clean/trace_{i}.csv', 'w') as f:
        dist = np.random.normal(128, 20, 1000)
        for step in range(15):
            # Shift by max 5.0 units per step (Wasserstein < 6.0)
            dist = dist + np.random.uniform(-5.0, 5.0)
            hist, _ = np.histogram(dist, bins=256, range=(0, 256))
            f.write(','.join(map(str, hist)) + '\n')

# 3. Generate evil corpus
np.random.seed(43)
for i in range(20):
    with open(f'/app/corpus/evil/trace_{i}.csv', 'w') as f:
        dist = np.random.normal(128, 20, 1000)
        for step in range(15):
            if step == 7:
                # Bug jump: Shift by 15.0 units (Wasserstein > 12.0)
                dist = dist + 15.0
            else:
                dist = dist + np.random.uniform(-5.0, 5.0)
            hist, _ = np.histogram(dist, bins=256, range=(0, 256))
            f.write(','.join(map(str, hist)) + '\n')
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
