#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc make
    pip3 install pytest numpy pillow

    mkdir -p /app/traces/clean
    mkdir -p /app/traces/evil

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
from PIL import Image
import subprocess

os.makedirs('/app/traces/clean', exist_ok=True)
os.makedirs('/app/traces/evil', exist_ok=True)
os.makedirs('/tmp/frames', exist_ok=True)

np.random.seed(42)

mu = 150000
sigma = 5000
width = 640
height = 480
total_pixels = width * height

for i in range(100):
    white_pixels = int(np.random.normal(mu, sigma))
    white_pixels = max(0, min(white_pixels, total_pixels))

    arr = np.zeros(total_pixels, dtype=np.uint8)
    arr[:white_pixels] = 255
    np.random.shuffle(arr)
    arr = arr.reshape((height, width))

    img = Image.fromarray(arr)
    img.save(f'/tmp/frames/frame_{i:03d}.png')

subprocess.run(['ffmpeg', '-y', '-framerate', '10', '-i', '/tmp/frames/frame_%03d.png', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '/app/diagnostic_screen.mp4'], check=True)

for i in range(50):
    clean_vals = np.random.normal(mu, sigma, 100)
    clean_vals = np.clip(clean_vals, 0, mu + 4*sigma - 1).astype(int)
    with open(f'/app/traces/clean/trace_{i:03d}.txt', 'w') as f:
        for val in clean_vals:
            f.write(f'{val}\n')

    evil_vals = np.random.normal(mu, sigma, 100).astype(int)
    spike_idx = np.random.randint(0, 100)
    evil_vals[spike_idx] = np.random.randint(175000, 250000)
    with open(f'/app/traces/evil/trace_{i:03d}.txt', 'w') as f:
        for val in evil_vals:
            f.write(f'{val}\n')
EOF

    python3 /tmp/setup.py

    chmod -R 755 /app/traces
    chmod 644 /app/diagnostic_screen.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
