#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++ make
    pip3 install pytest pandas scikit-learn opencv-python-headless numpy

    cat << 'EOF' > /tmp/setup.py
import os
import cv2
import numpy as np

os.makedirs('/app', exist_ok=True)

out = cv2.VideoWriter('/app/experiment_data.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (64, 64), isColor=False)
np.random.seed(42)

y_true = []
for i in range(200):
    frame = np.random.randint(0, 50, (64, 64), dtype=np.uint8)
    is_anomaly = 0
    if (20 <= i < 40) or (110 <= i < 130) or (160 <= i < 175):
        is_anomaly = 1
        cx, cy = np.random.randint(15, 50, 2)
        x, y = np.meshgrid(np.arange(64), np.arange(64))
        dist = (x - cx)**2 + (y - cy)**2
        cluster = 150 * np.exp(-dist / 15.0)
        frame = np.clip(frame + cluster, 0, 255).astype(np.uint8)

    y_true.append(is_anomaly)
    out.write(frame)

out.release()

with open('/app/ground_truth.txt', 'w') as f:
    for val in y_true:
        f.write(f"{val}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
