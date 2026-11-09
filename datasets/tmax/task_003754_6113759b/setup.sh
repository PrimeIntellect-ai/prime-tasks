#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --upgrade pip
    pip3 install pytest opencv-python-headless numpy scikit-learn fastapi uvicorn pydantic requests

    mkdir -p /app
    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np
import os

os.makedirs('/app', exist_ok=True)
out = cv2.VideoWriter('/app/sample_video.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
# 5 seconds dark (intensity ~ 50)
for _ in range(150):
    frame = np.full((480, 640, 3), 50, dtype=np.uint8)
    out.write(frame)
# 5 seconds bright (intensity ~ 200)
for _ in range(150):
    frame = np.full((480, 640, 3), 200, dtype=np.uint8)
    out.write(frame)
out.release()
EOF
    python3 /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
