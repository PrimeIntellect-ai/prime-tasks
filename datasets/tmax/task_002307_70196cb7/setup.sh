#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential ffmpeg libsm6 libxext6
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app

    # Generate the experiment video
    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np
import math

Cd = 0.05
vx0 = 15.0
vy0 = -20.0
frames = 300
dt = 1.0 / 60.0

x, y = 0.0, 0.0
vx, vy = vx0, vy0

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/experiment_video.mp4', fourcc, 60.0, (1920, 1080))

start_px_x = 200
start_px_y = 900

for _ in range(frames):
    img = np.zeros((1080, 1920, 3), dtype=np.uint8)

    px_x = int(start_px_x + x * 100)
    px_y = int(start_px_y + y * 100)

    # OpenCV uses BGR, so red is (0, 0, 255)
    cv2.circle(img, (px_x, px_y), 15, (0, 0, 255), -1)
    out.write(img)

    v_mag = math.sqrt(vx**2 + vy**2)
    ax = -Cd * v_mag * vx
    ay = 9.81 - Cd * v_mag * vy
    vx += ax * dt
    vy += ay * dt
    x += vx * dt
    y += vy * dt

out.release()
EOF

    python3 /tmp/generate_video.py
    rm /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
