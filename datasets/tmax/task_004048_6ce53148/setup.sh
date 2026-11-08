#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        acl \
        golang-go \
        openssl \
        curl \
        netcat-openbsd

    pip3 install pytest opencv-python-headless

    # Create the video artifact
    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/deploy_sequence.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (320, 240))
black = np.zeros((240, 320, 3), dtype=np.uint8)
white = np.ones((240, 320, 3), dtype=np.uint8) * 255

for _ in range(14):
    out.write(black)
for _ in range(16):
    out.write(white)
out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    # Create user
    useradd -m -s /bin/bash user || true

    # Ensure correct permissions
    chmod -R 777 /home/user
