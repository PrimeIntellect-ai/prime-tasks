#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nasm gcc curl
pip3 install pytest opencv-python-headless flask fastapi uvicorn

mkdir -p /app
cat << 'EOF' > /tmp/make_video.py
import cv2
import numpy as np

# Create a 300-frame video at 30fps
out = cv2.VideoWriter('/app/deployment_signal.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (64, 64))
for i in range(300):
    frame = np.zeros((64, 64, 3), dtype=np.uint8)
    if 101 <= i <= 245:
        frame[:, :] = (0, 0, 255) # OpenCV uses BGR format
    out.write(frame)
out.release()
EOF
python3 /tmp/make_video.py
rm /tmp/make_video.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
