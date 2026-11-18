#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np
import math

width, height = 16, 16
fps = 10
duration = 10
num_frames = fps * duration # 100 frames

out = cv2.VideoWriter('/app/binding_kinetics.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height), isColor=False)

for t in range(num_frames):
    # I(t) = 100 + 50 * sin(2*pi*3*t/100) + 20 * cos(2*pi*7*t/100)
    # Dominant frequency index should be 3
    val = 100.0 + 50.0 * math.sin(2 * math.pi * 3 * t / 100.0) + 20.0 * math.cos(2 * math.pi * 7 * t / 100.0)

    # Clip and convert to uint8
    val = max(0, min(255, int(round(val))))

    frame = np.full((height, width), val, dtype=np.uint8)
    out.write(frame)

out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
