#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang-go
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app

    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np
import os

os.makedirs('/app', exist_ok=True)
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/experiment.mp4', fourcc, 30.0, (800, 600), isColor=False)

g_px = 981.0
x, y = 50.0, 500.0
vx, vy = 200.0, -800.0
dt = 1/30.0

for frame_idx in range(60):
    # Create static background grid
    frame = np.ones((600, 800), dtype=np.uint8) * 200
    frame[0::50, :] = 150
    frame[:, 0::50] = 150

    # Draw projectile
    cv2.circle(frame, (int(x), int(y)), 15, 0, -1)

    out.write(frame)

    # Update physics
    x += vx * dt
    y += vy * dt + 0.5 * g_px * dt**2
    vy += g_px * dt

out.release()
EOF

    python3 /tmp/generate_video.py
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
