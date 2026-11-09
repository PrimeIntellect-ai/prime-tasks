#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install dependencies for the task and setup
    apt-get install -y libglib2.0-0 libsm6 libxext6 libxrender-dev
    pip3 install numpy opencv-python-headless pandas flask fastapi uvicorn

    # Create the video file
    mkdir -p /app
    cat << 'EOF' > /tmp/setup_video.py
import cv2
import numpy as np
import os

os.makedirs('/app', exist_ok=True)
out = cv2.VideoWriter('/app/experiment.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (64, 64), isColor=False)

# Ground truth trajectory: y = 30 + 20 * sin(0.2 * t)
for t in range(50):
    frame = np.zeros((64, 64), dtype=np.uint8)
    y = int(30 + 20 * np.sin(0.2 * t))
    x = 32

    # Introduce missing frames at t=10, 11, 25
    if t not in [10, 11, 25]:
        cv2.circle(frame, (x, y), 2, 255, -1)
    else:
        # Faint noise
        frame = np.random.randint(0, 50, (64, 64), dtype=np.uint8)

    out.write(frame)

out.release()
EOF
    python3 /tmp/setup_video.py
    rm /tmp/setup_video.py

    # Create the user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
