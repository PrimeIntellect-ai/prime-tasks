#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        libhdf5-dev \
        g++ \
        libgl1-mesa-glx \
        libglib2.0-0

    pip3 install pytest h5py numpy opencv-python-headless

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
import h5py
import os

# Generate video
width, height = 640, 480
fps = 30
duration = 10
frames = fps * duration
freq = 0.5
gamma = 0.1

out = cv2.VideoWriter('/app/experiment_video.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height))

for i in range(frames):
    t = i / fps
    x = int(width / 2 + 200 * np.exp(-gamma * t / 2) * np.cos(2 * np.pi * freq * t))
    y = int(height / 2)

    frame = np.zeros((height, width, 3), dtype=np.uint8)
    cv2.circle(frame, (x, y), 20, (255, 255, 255), -1)
    out.write(frame)

out.release()

# Generate HDF5 files
np.random.seed(42)

# Clean: 10 files
for i in range(10):
    with h5py.File(f'/app/corpus/clean/clean_{i}.h5', 'w') as f:
        f.create_dataset('gamma', data=0.1)
        f.create_dataset('omega_sq', data=9.8696 + np.random.uniform(-0.1, 0.1))
        f.create_dataset('dt', data=0.01)
        f.create_dataset('t_max', data=10.0)

# Evil: 20 files
# 10 unstable (dt = 2.5)
for i in range(10):
    with h5py.File(f'/app/corpus/evil/unstable_{i}.h5', 'w') as f:
        f.create_dataset('gamma', data=0.1)
        f.create_dataset('omega_sq', data=9.8696)
        f.create_dataset('dt', data=2.5)
        f.create_dataset('t_max', data=10.0)

# 10 wrong freq
for i in range(10):
    with h5py.File(f'/app/corpus/evil/wrong_freq_{i}.h5', 'w') as f:
        f.create_dataset('gamma', data=0.1)
        freq = 0.2 if i < 5 else 1.5
        omega = 2 * np.pi * freq
        f.create_dataset('omega_sq', data=omega**2)
        f.create_dataset('dt', data=0.01)
        f.create_dataset('t_max', data=10.0)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
