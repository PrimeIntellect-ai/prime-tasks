#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk bc jq
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

fps = 30
duration = 10
width, height = 200, 200
out = cv2.VideoWriter('/app/blinking.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height), isColor=False)

for i in range(fps * duration):
    t = i / fps
    brightness = 128 + 100 * np.sin(2 * np.pi * 2.5 * t)
    # Ensure brightness is within valid range
    brightness = np.clip(brightness, 0, 255)
    frame = np.full((height, width), brightness, dtype=np.uint8)
    out.write(frame)

out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
