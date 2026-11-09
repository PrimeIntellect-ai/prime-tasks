#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest numpy scipy opencv-python-headless

    mkdir -p /app

    cat << 'EOF' > /app/setup.py
import os
import json
import numpy as np
import cv2
from scipy.stats import wasserstein_distance

os.makedirs('/app', exist_ok=True)

# Generate reference distribution (a mix of two Gaussians)
x = np.arange(256)
ref_pdf = np.exp(-0.5 * ((x - 50) / 10)**2) + 0.5 * np.exp(-0.5 * ((x - 180) / 15)**2)
ref_pdf /= np.sum(ref_pdf)
with open('/app/ref_dist.json', 'w') as f:
    json.dump(ref_pdf.tolist(), f)

# Generate a synthetic video where the frame histograms slowly converge to a slightly shifted ref_dist
width, height = 100, 100
fps = 10
duration = 10 # 100 frames
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/sequencing_droplets.mp4', fourcc, fps, (width, height), False)

np.random.seed(42)
for i in range(1, duration * fps + 1):
    # As i increases, the target mean shifts closer to the ref_dist means
    shift = 20 * np.exp(-i / 20.0) 

    # Generate pixels
    pixels1 = np.random.normal(loc=50 + shift, scale=10, size=int(width*height*0.66))
    pixels2 = np.random.normal(loc=180 + shift, scale=15, size=int(width*height*0.34))
    frame_pixels = np.concatenate([pixels1, pixels2])
    frame_pixels = np.clip(frame_pixels, 0, 255).astype(np.uint8)
    np.random.shuffle(frame_pixels)

    frame = frame_pixels.reshape((height, width))
    out.write(frame)

out.release()
EOF

    python3 /app/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
