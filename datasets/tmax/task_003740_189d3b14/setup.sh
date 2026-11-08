#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libglib2.0-0 libgl1-mesa-glx
    pip3 install --default-timeout=100 pytest numpy opencv-python-headless

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/setup.py
import os
import cv2
import csv
import random
import numpy as np
import shutil

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

# 1. Generate Video
frames = []
np.random.seed(42)
total_edges = 0
for f in range(50):
    img = np.zeros((10, 10, 3), dtype=np.uint8)
    for _ in range(2): # max 2 edges per frame
        src, dst = np.random.randint(0, 10, 2)
        if src != dst and np.random.rand() > 0.1:
            img[src, dst] = [255, 255, 255]
            total_edges += 1
    frames.append(img)

out = cv2.VideoWriter('/app/experiment_001.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10.0, (10, 10))
for frame in frames:
    out.write(frame)
out.release()

# 2. Generate Corpora
def write_csv(path, edges):
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['frame', 'source', 'target'])
        writer.writerows(edges)

# Clean: Max 7 edges in any 5-frame window for any node
for i in range(5):
    edges = []
    for f in range(20):
        # Sparse, safe edges
        edges.append((f, i, (i+1)%10))
    write_csv(f'/app/corpus/clean/clean_{i}.csv', edges)

# Evil: Violates the > 7 edges in 5-frame window rule
for i in range(5):
    edges = []
    # Burst of 8 edges for node 0 in frames 2..4
    for f in range(2, 5):
        for t in range(1, 4):
            edges.append((f, 0, t))
    write_csv(f'/app/corpus/evil/evil_{i}.csv', edges)
EOF

    python3 /app/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
