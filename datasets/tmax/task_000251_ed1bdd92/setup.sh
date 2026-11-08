#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends python3 python3-pip ffmpeg g++ libglib2.0-0
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/vnc_session.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (320, 240))
for i in range(300):
    if i >= 143:
        # Inverted screen starting at frame 143
        frame = np.full((240, 320, 3), (0, 0, 255), dtype=np.uint8)
    else:
        frame = np.full((240, 320, 3), (255, 0, 0), dtype=np.uint8)
    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
