#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang-go python3-opencv python3-numpy
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np
import os

os.makedirs('/app', exist_ok=True)
out = cv2.VideoWriter('/app/experiment.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10.0, (100, 100), isColor=False)

for i in range(40):
    val = 50 + i * 2
    if i == 10:
        val = 0 # Missing value
    elif i == 20:
        val = 255 # Outlier

    frame = np.full((100, 100), val, dtype=np.uint8)
    out.write(frame)

out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
