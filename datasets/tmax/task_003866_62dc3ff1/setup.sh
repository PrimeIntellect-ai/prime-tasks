#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        nodejs \
        perl \
        ruby \
        gawk \
        g++ \
        libglib2.0-0

    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

# Create a 95-second video at 5 FPS (475 frames)
out = cv2.VideoWriter('/app/manufacturing_feed.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 5, (64, 64))
for i in range(5 * 95):
    t = i / 5.0
    frame = np.zeros((64, 64, 3), dtype=np.uint8)

    # Create anomalies at exactly 14.2s, 42.6s, and 89.0s
    if abs(t - 14.2) < 0.01 or abs(t - 42.6) < 0.01 or abs(t - 89.0) < 0.01:
        frame.fill(255)

    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
