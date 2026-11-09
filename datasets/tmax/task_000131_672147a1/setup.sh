#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /home/user/frames

    cat << 'EOF' > /tmp/generate_data.py
import cv2
import numpy as np
import os
import random
import math

# Generate video
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/experiment.mp4', fourcc, 10.0, (320, 240), isColor=False)
for i in range(100):
    frame = np.zeros((240, 320), dtype=np.uint8)
    x = int(160 + 100 * math.sin(i * 0.1))
    y = int(120 + 50 * math.cos(i * 0.1))
    cv2.circle(frame, (x, y), 3, 255, -1)
    out.write(frame)
out.release()

# Generate clean corpus
for i in range(1, 51):
    with open(f'/app/corpora/clean/run_{i:02d}.csv', 'w') as f:
        f.write("frame_id,x,y\n")
        for j in range(100):
            x = int(160 + 100 * math.sin(j * 0.1) + random.gauss(0, 2))
            y = int(120 + 50 * math.cos(j * 0.1) + random.gauss(0, 2))
            f.write(f"{j},{x},{y}\n")

# Generate evil corpus
for i in range(1, 51):
    with open(f'/app/corpora/evil/corrupt_{i:02d}.csv', 'w') as f:
        f.write("frame_id,x,y\n")
        for j in range(100):
            if random.random() < 0.05:
                f.write(f"{j},-1,-1\n")
            elif random.random() < 0.05:
                x = int(160 + 100 * math.sin(j * 0.1) + random.gauss(0, 2) + random.choice([-50, 50]))
                y = int(120 + 50 * math.cos(j * 0.1) + random.gauss(0, 2) + random.choice([-50, 50]))
                f.write(f"{j},{x},{y}\n")
            else:
                x = int(160 + 100 * math.sin(j * 0.1) + random.gauss(0, 2))
                y = int(120 + 50 * math.cos(j * 0.1) + random.gauss(0, 2))
                f.write(f"{j},{x},{y}\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
