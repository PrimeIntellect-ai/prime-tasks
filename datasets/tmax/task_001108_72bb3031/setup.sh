#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy opencv-python-headless scikit-learn joblib

    mkdir -p /app
    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
import os

os.makedirs('/app', exist_ok=True)
out = cv2.VideoWriter('/app/calibration_video.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (128, 128), isColor=False)

for i in range(300):
    frame = np.zeros((128, 128), dtype=np.uint8)
    # Moving circle
    center = (int(10 + i * (108/300)), int(64 + 30 * np.sin(i / 10.0)))
    cv2.circle(frame, center, 15, 255, -1)
    # Add some noise
    noise = np.random.randint(0, 50, (128, 128), dtype=np.uint8)
    frame = cv2.add(frame, noise)
    out.write(frame)

out.release()
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
