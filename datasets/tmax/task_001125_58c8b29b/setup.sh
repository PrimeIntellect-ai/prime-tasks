#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang python3-opencv python3-numpy
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import os
import cv2
import numpy as np
import json

os.makedirs('/app', exist_ok=True)

graph_data = {
    "A": ["B", "D"],
    "B": ["A", "C", "E"],
    "C": ["B"],
    "D": ["A"],
    "E": ["B"]
}
with open('/app/graph.json', 'w') as f:
    json.dump(graph_data, f)

fps = 30
duration = 10
frames = fps * duration

freqs = {"A": 2.0, "B": 3.0, "C": 1.0}
boxes = {
    "A": (50, 50, 20, 20),
    "B": (150, 50, 20, 20),
    "C": (100, 150, 20, 20)
}

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/experiment.mp4', fourcc, fps, (300, 300), isColor=False)

for i in range(frames):
    t = i / fps
    img = np.zeros((300, 300), dtype=np.uint8)

    for node, (x, y, w, h) in boxes.items():
        f = freqs[node]
        intensity = int(102.5 * np.sin(2 * np.pi * f * t) + 152.5)
        img[y:y+h, x:x+w] = intensity

    out.write(img)

out.release()
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
