#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-opencv gcc ffmpeg
pip3 install pytest flask fastapi uvicorn requests

mkdir -p /app
cat << 'EOF' > /tmp/make_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/diffusion.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (64, 64))
frame = np.zeros((64, 64, 3), dtype=np.uint8)
frame[27:37, 27:37, :] = 255
for _ in range(20):
    out.write(frame)
out.release()
EOF
python3 /tmp/make_video.py
rm /tmp/make_video.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
