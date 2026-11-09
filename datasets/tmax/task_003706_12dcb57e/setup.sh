#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        libgomp1 \
        ffmpeg \
        libsm6 \
        libxext6

    pip3 install pytest numpy scipy opencv-python-headless fbm flask fastapi uvicorn requests

    mkdir -p /app

    # Generate the experiment video
    cat << 'EOF' > /tmp/gen_video.py
import numpy as np
import cv2
from fbm import FBM

n = 300
H = 0.375 # alpha = 0.75 -> H = alpha / 2
length = 10.0 # 300 frames at 30 FPS = 10 seconds

f_x = FBM(n=n, hurst=H, length=length)
f_y = FBM(n=n, hurst=H, length=length)

x = f_x.fbm()
y = f_y.fbm()

# D = 1.5, so Var = 2 * D * t^alpha
scale = np.sqrt(2 * 1.5)
x = x * scale
y = y * scale

# We will just use the coordinates directly, shifted to center
px = np.clip(np.round(x * 10 + 256).astype(int), 0, 511)
py = np.clip(np.round(y * 10 + 256).astype(int), 0, 511)

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/experiment.mp4', fourcc, 30.0, (512, 512), False)

for i in range(n):
    frame = np.zeros((512, 512), dtype=np.uint8)
    cv2.circle(frame, (px[i], py[i]), 5, 255, -1)
    out.write(frame)

out.release()
EOF

    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
