#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libhdf5-dev curl
    pip3 install pytest numpy opencv-python-headless h5py flask requests

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

# A=150, B=1.5, C=20
A, B, C = 150.0, 1.5, 20.0
fps = 10
frames = 50

out = cv2.VideoWriter('/app/fluorescence.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (100, 100), False)
for i in range(frames):
    t = i / fps
    intensity = A * np.exp(-B * t) + C
    # Add minor noise
    noise = np.random.normal(0, 1.0)
    val = np.clip(intensity + noise, 0, 255)

    frame = np.full((100, 100), int(val), dtype=np.uint8)
    out.write(frame)

out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
