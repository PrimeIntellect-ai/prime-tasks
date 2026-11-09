#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg git curl
pip3 install pytest opencv-python-headless numpy

mkdir -p /app
cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np

# Create a 5-second video at 10 fps (50 frames total)
out = cv2.VideoWriter('/app/dashboard.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (640, 480))

for i in range(50):
    if (10 <= i <= 14) or (30 <= i <= 38):
        # Red frames: 5 + 9 = 14 frames total
        frame = np.zeros((480, 640, 3), dtype=np.uint8)
        frame[:] = (0, 0, 255) # BGR format
    else:
        # Black frames
        frame = np.zeros((480, 640, 3), dtype=np.uint8)
    out.write(frame)

out.release()
EOF
python3 /tmp/generate_video.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
