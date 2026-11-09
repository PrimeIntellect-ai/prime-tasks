#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libgsl-dev gcc
    pip3 install pytest numpy scipy opencv-python-headless

    mkdir -p /app
    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np
import scipy.stats as stats

# Set a fixed seed and true parameters
np.random.seed(42)
true_k = 4.5
true_theta = 3.2

# Generate 120 samples from Gamma distribution
samples = np.round(np.random.gamma(shape=true_k, scale=true_theta, size=120)).astype(int)

# Create video
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/system_monitor.mp4', fourcc, 10.0, (100, 100))

for count in samples:
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    # randomly place 'count' white pixels
    coords = set()
    while len(coords) < count:
        x = np.random.randint(0, 100)
        y = np.random.randint(0, 100)
        coords.add((x, y))

    for (x, y) in coords:
        frame[y, x] = [255, 255, 255]

    out.write(frame)

out.release()
EOF

    python3 /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
