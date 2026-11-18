#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app
    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/fluorescence.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (400, 400))
for t in range(100):
    img = np.zeros((400, 400, 3), dtype=np.uint8)
    x = int(100 + 2.0 * t)
    y = int(100 + 1.0 * t + 10.0 * np.sin(0.1 * t))
    cv2.circle(img, (x, y), 3, (255, 255, 255), -1)
    out.write(img)
out.release()
EOF

    python3 /tmp/generate_video.py
    rm /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
