#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy opencv-python-headless matplotlib

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np
import cv2
import matplotlib.pyplot as plt

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

# Generate clean
for i in range(20):
    fig, ax = plt.subplots(figsize=(4, 3), dpi=100)
    ax.plot(np.random.rand(10))
    fig.savefig(f'/app/corpus/clean/clean_{i}.png')
    plt.close(fig)

# Generate evil
for i in range(20):
    if i % 2 == 0:
        img = np.ones((300, 400, 3), dtype=np.uint8) * 255
    else:
        img = np.zeros((300, 400, 3), dtype=np.uint8)
    cv2.imwrite(f'/app/corpus/evil/evil_{i}.png', img)

# Generate video
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/experiment_record.mp4', fourcc, 10.0, (400, 300))

evil_indices = [14, 15, 16, 55, 92, 110, 111, 148]

for i in range(150):
    if i in evil_indices:
        img = cv2.imread(f'/app/corpus/evil/evil_{i % 20}.png')
    else:
        img = cv2.imread(f'/app/corpus/clean/clean_{i % 20}.png')
    img = cv2.resize(img, (400, 300))
    out.write(img)
out.release()
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
