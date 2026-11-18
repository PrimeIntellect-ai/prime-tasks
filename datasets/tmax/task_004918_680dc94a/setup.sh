#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libgl1 libglib2.0-0
    pip3 install pytest numpy opencv-python-headless scipy flask

    # Generate the video artifact
    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np
import os

os.makedirs('/app', exist_ok=True)
out = cv2.VideoWriter('/app/integrator_profile.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (640, 480))

for i in range(100):
    img = np.zeros((480, 640, 3), dtype=np.uint8)
    x = i * 6
    if i < 50:
        y = 240
    else:
        y = 240 + (i - 50) * 2

    img[y:y+2, x:x+2] = [0, 0, 255] # BGR format in OpenCV -> Red
    out.write(img)

out.release()
EOF
    python3 /tmp/generate_video.py
    rm /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
