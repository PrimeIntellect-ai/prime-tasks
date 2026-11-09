#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake g++ make libopencv-dev
    pip3 install pytest numpy pandas opencv-python-headless

    mkdir -p /app

    cat << 'EOF' > /tmp/generate_data.py
import cv2
import numpy as np
import pandas as pd
import os

width, height = 640, 480
fps = 30
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/experiment_run.mp4', fourcc, fps, (width, height))

frames = 60
gt_data = []

for i in range(frames):
    img = np.zeros((height, width, 3), dtype=np.uint8)

    # Parabolic path
    x = int(50 + (540 / (frames - 1)) * i)
    h = 320
    k = 100
    a = (400 - k) / ((50 - h)**2)
    y = int(a * (x - h)**2 + k)

    cv2.circle(img, (x, y), 5, (255, 255, 255), -1)
    out.write(img)
    gt_data.append({'frame': i, 'x': x, 'y': y})

out.release()

df = pd.DataFrame(gt_data)
df.to_csv('/app/ground_truth.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
