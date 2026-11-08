#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy opencv-python-headless scipy flask pandas requests

    mkdir -p /app

    # Generate the video
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

# 400x800, 30 fps
out = cv2.VideoWriter('/app/drop_test.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30.0, (400, 800))

for i in range(27):
    frame = np.zeros((800, 400, 3), dtype=np.uint8)
    y = int(50 + 1.09 * (i**2))
    if y < 800:
        cv2.circle(frame, (200, y), 10, (255, 255, 255), -1)
    out.write(frame)

out.release()
EOF

    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
