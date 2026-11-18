#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3
pip3 install pytest opencv-python-headless numpy

mkdir -p /app
cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/network_feed.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (64, 64))
for f in range(1000):
    frame = np.zeros((64, 64, 3), dtype=np.uint8)
    if f % 3 == 0:
        frame[32, 32] = [0, 0, 255] # BGR format
    out.write(frame)
out.release()
EOF
python3 /tmp/gen_video.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
