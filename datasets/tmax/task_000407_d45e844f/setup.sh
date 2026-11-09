#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy numpy opencv-python-headless

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import cv2
import json
import os

np.random.seed(42)
baseline_latencies = np.random.normal(30, 5, 300).clip(0, 255).astype(int)

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/ui_test_run.mp4', fourcc, 30.0, (100, 100))

for lat in baseline_latencies:
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    frame[:, :, 2] = lat
    out.write(frame)
out.release()

for i in range(10):
    clean_trace = np.random.normal(30, 5, 300).clip(0, 255).astype(int).tolist()
    with open(f"/app/corpus/clean/trace_{i}.json", "w") as f:
        json.dump(clean_trace, f)

for i in range(10):
    evil_trace = np.random.normal(45, 5, 300).clip(0, 255).astype(int).tolist()
    with open(f"/app/corpus/evil/trace_{i}.json", "w") as f:
        json.dump(evil_trace, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
