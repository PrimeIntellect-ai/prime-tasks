#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy opencv-python-headless flask fastapi uvicorn pillow

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
import numpy as np
import cv2
import os

out_dir = "/app"
os.makedirs(out_dir, exist_ok=True)
video_path = os.path.join(out_dir, "reaction_spectroscopy.mp4")

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter(video_path, fourcc, 10.0, (100, 100), isColor=False)

for t in range(100):
    frame = np.zeros((100, 100), dtype=np.uint8)
    # create some signal on row 49
    # Component 1: Gaussian at col 30
    c1 = 100 * np.exp(-((np.arange(100) - 30)**2) / 20) * (t / 100)
    # Component 2: Gaussian at col 70
    c2 = 100 * np.exp(-((np.arange(100) - 70)**2) / 20) * (1 - t / 100)

    signal = np.clip(c1 + c2, 0, 255).astype(np.uint8)
    frame[49, :] = signal
    out.write(frame)

out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
