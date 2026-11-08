#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6
    pip3 install pytest numpy opencv-python-headless flask fastapi uvicorn requests

    mkdir -p /app

    # Generate the dirty_feed.mp4 video
    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np

fps = 10
width, height = 640, 480
out = cv2.VideoWriter('/app/dirty_feed.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height))

frame = np.zeros((height, width, 3), dtype=np.uint8)

for i in range(1, 301):
    if 50 <= i <= 60:
        # Pitch black
        current_frame = np.zeros((height, width, 3), dtype=np.uint8)
    elif 100 <= i <= 120:
        # Frozen frame (identical to frame 99)
        current_frame = frame.copy()
    else:
        # Changing frame
        current_frame = np.full((height, width, 3), (i % 255, (i * 2) % 255, (i * 3) % 255), dtype=np.uint8)
        frame = current_frame.copy()

    out.write(current_frame)

out.release()
EOF
    python3 /tmp/generate_video.py
    rm /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
