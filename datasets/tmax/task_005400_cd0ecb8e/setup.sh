#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libglib2.0-0
    pip3 install pytest opencv-python-headless numpy pandas

    mkdir -p /app/truth

    cat << 'EOF' > /app/setup.py
import cv2
import numpy as np
import random
import os

os.makedirs('/app', exist_ok=True)
os.makedirs('/app/truth', exist_ok=True)

width, height = 500, 500
fps = 10
frames = 300
out = cv2.VideoWriter('/app/grid_flash.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height), isColor=False)

random.seed(42)
adjacency = set()
for r in range(5):
    for c in range(5):
        i = r * 5 + c
        if c < 4: adjacency.add((i, i+1))
        if r < 4: adjacency.add((i, i+5))

edge_weights = {edge: 0 for edge in adjacency}

for f in range(frames):
    img = np.zeros((height, width), dtype=np.uint8)

    # randomly turn on some edges
    active_edges = random.sample(list(adjacency), k=3)
    active_nodes = set()
    for u, v in active_edges:
        active_nodes.add(u)
        active_nodes.add(v)
        edge_weights[(u, v)] += 1

    for r in range(5):
        for c in range(5):
            i = r * 5 + c
            if i in active_nodes:
                cv2.rectangle(img, (c*100, r*100), ((c+1)*100, (r+1)*100), 255, -1)

    out.write(img)

out.release()

with open('/app/truth/reference.csv', 'w') as f:
    f.write("source,target,weight\n")
    for (u, v), w in sorted(edge_weights.items(), key=lambda x: x[1], reverse=True):
        if w > 0:
            f.write(f"{u},{v},{w}\n")
EOF

    python3 /app/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
