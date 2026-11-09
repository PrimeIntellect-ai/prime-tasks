#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy opencv-python-headless scipy fastapi uvicorn requests

    mkdir -p /app

    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/rendering.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100))
np.random.seed(0)

for i in range(30):
    if i % 10 == 0:
        # Anomalous frame (numerical instability)
        frame = np.random.normal(128, 50, (100, 100)).clip(0, 255).astype(np.uint8)
    else:
        # Stable frame following Beta(2,5)
        frame = (np.random.beta(2.0, 5.0, (100, 100)) * 255).astype(np.uint8)

    frame_color = cv2.cvtColor(frame, cv2.COLOR_GRAY2BGR)
    out.write(frame_color)
out.release()
EOF

    python3 /tmp/generate_video.py
    rm /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
