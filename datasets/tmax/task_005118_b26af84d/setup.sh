#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg acl
    pip3 install pytest opencv-python-headless

    mkdir -p /app
    mkdir -p /home/user

    # Generate the video with exactly 5 black frames
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/camera_01.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 5, (320, 240))
black = np.zeros((240, 320, 3), dtype=np.uint8)
white = np.ones((240, 320, 3), dtype=np.uint8) * 255

# Write 5 black frames
for _ in range(5):
    out.write(black)
# Write 10 white frames
for _ in range(10):
    out.write(white)
out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
