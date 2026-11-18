#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-opencv curl
    pip3 install pytest numpy flask fastapi uvicorn requests

    mkdir -p /app

    cat << 'EOF' > /tmp/make_video.py
import cv2
import numpy as np

frames = [
    (10, 20),
    (30, 25),
    (50, 50),
    (70, 25),
    (90, 20)
]

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/movement_log.mp4', fourcc, 1.0, (100, 100))

for x, y in frames:
    img = np.zeros((100, 100, 3), dtype=np.uint8)
    img[y, x] = [255, 255, 255]
    out.write(img)

out.release()
EOF
    python3 /tmp/make_video.py
    rm /tmp/make_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
