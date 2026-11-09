#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy scipy opencv-python-headless pillow

    mkdir -p /app
    cat << 'EOF' > /app/generate_video.py
import numpy as np
import cv2

D = 0.015
L = 1.0
T = 10.0
fps = 10
frames = int(T * fps) + 1
width = 400
height = 50

out = cv2.VideoWriter('/app/biosensor_timelapse.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height), False)

x = np.linspace(0, L, width)
for i in range(frames):
    t = i / fps
    # Avoid division by zero
    if t < 0.01:
        t = 0.01

    sigma = np.sqrt(2 * D * t)
    c = np.exp(-((x - 0.5)**2) / (2 * sigma**2)) / (sigma * np.sqrt(2*np.pi))

    # Scale for visual intensity, peak at t=0.01 is around 13
    intensity = (c / 15.0) * 255
    intensity = np.clip(intensity, 0, 255).astype(np.uint8)

    frame = np.tile(intensity, (height, 1))
    out.write(frame)

out.release()
EOF

    python3 /app/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
