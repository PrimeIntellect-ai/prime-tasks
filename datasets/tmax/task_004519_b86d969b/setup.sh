#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6 libgl1 libglib2.0-0
    pip3 install pytest opencv-python numpy scipy

    mkdir -p /app
    cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np

width, height = 640, 480
A = 400
k = 0.025
C = 100
num_frames = 200

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/reaction_spectroscopy.mp4', fourcc, 30.0, (width, height))

for t in range(num_frames):
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    # Calculate peak position
    x_center = int(A * np.exp(-k * t) + C)
    y_center = height // 2

    # Draw a simulated Gaussian peak (using a blurred circle)
    cv2.circle(frame, (x_center, y_center), 15, (255, 255, 255), -1)
    frame = cv2.GaussianBlur(frame, (31, 31), 0)

    out.write(frame)

out.release()
EOF

    python3 /app/generate_video.py
    rm /app/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
