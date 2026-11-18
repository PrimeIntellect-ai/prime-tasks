#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg cargo rustc
pip3 install pytest numpy opencv-python-headless

# Create app directory
mkdir -p /app/corpus/clean /app/corpus/evil

# Generate fixture data
cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np
import cv2
import csv

# Generate Video (3 Hz oscillation)
fps = 30
duration = 10
num_frames = fps * duration
freq = 3.0

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/machine_run.mp4', fourcc, fps, (100, 100), isColor=False)

for i in range(num_frames):
    t = i / fps
    # Brightness oscillates
    brightness = int(125 + 75 * np.sin(2 * np.pi * freq * t))
    frame = np.full((100, 100), brightness, dtype=np.uint8)
    out.write(frame)
out.release()

# Generate traces
np.random.seed(42)
fs = 100
num_samples = fs * duration
t = np.arange(num_samples) / fs

for i in range(50):
    noise = np.random.normal(0, 200, num_samples)
    clean_latency = 5000 + 2000 * np.sin(2 * np.pi * freq * t) + noise
    evil_latency = clean_latency + 1500 * np.sin(2 * np.pi * 15 * t)

    with open(f"/app/corpus/clean/trace_{i}.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["time_ms", "latency_us"])
        for j in range(num_samples):
            writer.writerow([int(t[j]*1000), int(clean_latency[j])])

    with open(f"/app/corpus/evil/trace_{i}.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["time_ms", "latency_us"])
        for j in range(num_samples):
            writer.writerow([int(t[j]*1000), int(evil_latency[j])])
EOF

python3 /tmp/generate_data.py
rm /tmp/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
