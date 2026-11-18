#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libgl1 libglib2.0-0
    pip3 install pytest numpy scipy flask requests opencv-python-headless

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

# Create video
fps = 30
duration = 10 # seconds
num_frames = fps * duration
width, height = 100, 100
video_path = '/app/flicker_experiment.mp4'

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter(video_path, fourcc, fps, (width, height))

np.random.seed(42)
# Dominant frequency: 4.5 Hz
f0 = 4.5
time = np.arange(num_frames) / fps

for t_idx, t in enumerate(time):
    # Base intensity 100, amplitude 40, plus some Gaussian noise
    intensity = 100 + 40 * np.sin(2 * np.pi * f0 * t) + np.random.normal(0, 5)
    intensity = np.clip(intensity, 0, 255)

    # create frame
    frame = np.full((height, width, 3), intensity, dtype=np.uint8)
    out.write(frame)

out.release()
EOF

    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
