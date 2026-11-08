#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick g++
    pip3 install pytest numpy pandas opencv-python-headless

    mkdir -p /app
    cat << 'EOF' > /app/generate.py
import numpy as np
import cv2
import pandas as pd

np.random.seed(42)
states = np.random.randint(0, 256, size=(100, 16))

glitch_frames = [15, 33, 34, 80]
for f in glitch_frames:
    states[f] = 0

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/sensor_feed.mp4', fourcc, 10.0, (400, 400), False)

for i in range(100):
    frame = np.zeros((400, 400), dtype=np.uint8)
    for row in range(4):
        for col in range(4):
            idx = row * 4 + col
            val = states[i, idx]
            frame[row*100:(row+1)*100, col*100:(col+1)*100] = val
    out.write(frame)
out.release()

clean_states = states.copy()
for i in range(1, 100):
    if i in glitch_frames:
        clean_states[i] = clean_states[i-1]

filtered = np.zeros_like(clean_states, dtype=int)
for i in range(100):
    prev_i = max(0, i-1)
    next_i = min(99, i+1)
    filtered[i] = clean_states[prev_i] - 2*clean_states[i] + clean_states[next_i]

pd.DataFrame(filtered).to_csv('/app/ground_truth_filtered.csv', index=False, header=False)
EOF

    python3 /app/generate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
