#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6 libgl1
    pip3 install pytest numpy opencv-python

    mkdir -p /app

    cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np
import random

random.seed(42)
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/data_stream.mp4', fourcc, 30.0, (100, 100), isColor=False)

for i in range(200):
    if random.random() > 0.8:
        frame = np.full((100, 100), 200, dtype=np.uint8)
    else:
        frame = np.full((100, 100), 50, dtype=np.uint8)
    out.write(frame)

out.release()
EOF

    python3 /app/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
