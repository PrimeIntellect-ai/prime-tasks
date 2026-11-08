#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libglib2.0-0
    pip3 install pytest numpy opencv-python-headless scipy flask fastapi uvicorn

    cat << 'EOF' > /tmp/setup.py
import os
import cv2
import numpy as np

# Create the /app directory
os.makedirs("/app", exist_ok=True)

# Generate the video
video_path = "/app/experiment_feed.mp4"
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter(video_path, fourcc, 10.0, (64, 64), False)

# Peak 1 at k=30 (omega=250), Peak 2 at k=70 (omega=450)
for k in range(100):
    # Lorentzian 1: A=50, gamma=25 (which is 5 in k-space)
    # Lorentzian 2: A=80, gamma=40 (which is 8 in k-space)
    # Baseline: C = 20
    val_1 = 50.0 * (5**2) / ((k - 30)**2 + 5**2)
    val_2 = 80.0 * (8**2) / ((k - 70)**2 + 8**2)
    intensity = val_1 + val_2 + 20.0

    # Clip to valid uint8 range just in case
    intensity = np.clip(intensity, 0, 255)

    # Create a 64x64 frame with this mean intensity
    frame = np.full((64, 64), int(intensity), dtype=np.uint8)
    out.write(frame)

out.release()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
