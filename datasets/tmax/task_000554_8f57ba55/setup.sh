#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libgl1-mesa-glx libglib2.0-0 ffmpeg
    pip3 install --default-timeout=100 pytest numpy pandas scikit-learn opencv-python

    mkdir -p /app
    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np
import os

os.makedirs('/app', exist_ok=True)
output_path = '/app/reaction.mp4'
fps = 10
frames = 100
width, height = 100, 100

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter(output_path, fourcc, fps, (width, height))

for i in range(frames):
    # Linear transition from pure Red (0,0,255 in BGR) to pure Blue (255,0,0)
    # Add a tiny bit of noise to make PCA non-trivial but clean
    r = int(255.0 - (255.0 * i / (frames - 1)))
    g = 10 + int(10 * np.sin(i / 10.0)) # slight non-linear noise
    b = int(255.0 * i / (frames - 1))

    frame = np.zeros((height, width, 3), dtype=np.uint8)
    frame[:, :] = [b, g, r] # OpenCV uses BGR
    out.write(frame)

out.release()
EOF

    python3 /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
