#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip python3-opencv python3-numpy \
        rustc cargo pkg-config libhdf5-dev \
        libavcodec-dev libavformat-dev libavutil-dev libswscale-dev clang \
        ffmpeg

    pip3 install pytest h5py

    mkdir -p /app
    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np

fps = 60
duration = 10
frames = fps * duration
freq = 5.34

out = cv2.VideoWriter('/app/reactor_vibration.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (200, 200))

for i in range(frames):
    t = i / fps
    val = np.sin(2 * np.pi * freq * t)
    intensity = int((val + 1) / 2 * 255)

    frame = np.zeros((200, 200, 3), dtype=np.uint8)
    frame[0:100, 0:100] = (intensity, intensity, intensity)

    out.write(frame)

out.release()
EOF
    python3 /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/vibration_analyzer
    chmod -R 777 /home/user
