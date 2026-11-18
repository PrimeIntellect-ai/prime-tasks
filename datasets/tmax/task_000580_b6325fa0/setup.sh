#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-opencv python3-numpy socat logrotate git
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/telemetry.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
for i in range(900):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    # Add random noise
    cv2.randn(frame, 50, 20)
    # Frame indices to have the red box: multiples of 20
    if i % 20 == 0:
        frame[0:50, 0:50] = [0, 0, 255] # BGR format: Pure Red
    out.write(frame)
out.release()
EOF
python3 /tmp/generate_video.py
rm /tmp/generate_video.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
