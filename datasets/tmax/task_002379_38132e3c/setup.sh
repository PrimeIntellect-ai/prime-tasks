#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg g++
    pip3 install pytest numpy pandas opencv-python-headless

    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
import subprocess
import os

np.random.seed(42)
os.makedirs("/app", exist_ok=True)

# Generate 10 frames
frames = []
expected_stats = {i: {'out': 0, 'in': 0} for i in range(10)}

for f in range(10):
    matrix = np.random.choice([0, 1], size=(10, 10), p=[0.7, 0.3])
    # 1 is edge (black), 0 is no edge (white)
    img = np.zeros((100, 100, 3), dtype=np.uint8)
    img.fill(255) # default white

    for i in range(10):
        for j in range(10):
            if matrix[i, j] == 1:
                img[i*10:(i+1)*10, j*10:(j+1)*10] = 0 # black
                expected_stats[i]['out'] += 1
                expected_stats[j]['in'] += 1

    cv2.imwrite(f"/tmp/frame_{f:02d}.png", img)

# Create video
subprocess.run([
    "ffmpeg", "-y", "-framerate", "1", "-i", "/tmp/frame_%02d.png",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "/app/graph_evolution.mp4"
], check=True)

# Write truth CSV for verifier
with open("/tmp/truth_node_stats.csv", "w") as f:
    f.write("node,total_out_weight,total_in_weight\n")
    for i in range(10):
        f.write(f"{i},{expected_stats[i]['out']},{expected_stats[i]['in']}\n")
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
