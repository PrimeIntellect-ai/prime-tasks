#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy emcee opencv-python-headless

    mkdir -p /app
    cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np

fps = 30
width, height = 640, 480
A = 150.0
gamma = 0.2
omega = 3.14159
phi = 0.0
x0 = 320.0
sigma = 2.0
num_frames = 300

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/experiment.mp4', fourcc, fps, (width, height))

np.random.seed(42)
for i in range(num_frames):
    t = i / fps
    x = A * np.exp(-gamma * t) * np.cos(omega * t + phi) + x0
    x_noisy = x + np.random.normal(0, sigma)

    frame = np.zeros((height, width, 3), dtype=np.uint8)
    cv2.circle(frame, (int(x_noisy), height//2), 10, (255, 255, 255), -1)
    out.write(frame)

out.release()
EOF

    python3 /app/generate_video.py
    rm /app/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
