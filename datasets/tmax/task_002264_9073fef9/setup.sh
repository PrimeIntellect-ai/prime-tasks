#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest numpy opencv-python-headless

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import os
import cv2
import numpy as np

os.makedirs('/app', exist_ok=True)

oracle_code = """import sys

def simulate(seed, num_steps, K=25):
    state = seed
    pos = 0
    for _ in range(num_steps):
        for _ in range(K):
            state = (1103515245 * state + 12345) % (2**31)
            pos += (state % 3) - 1
    print(pos)

if __name__ == "__main__":
    simulate(int(sys.argv[1]), int(sys.argv[2]))
"""
with open('/app/oracle_sim.py', 'w') as f:
    f.write(oracle_code)
os.chmod('/app/oracle_sim.py', 0o755)

np.random.seed(42)
num_frames = 600
K_video = 25
width, height = 64, 64

micro_steps = np.random.randint(0, 3, size=(num_frames, K_video)) - 1
macro_steps = np.sum(micro_steps, axis=1)

positions = np.cumsum(macro_steps)
positions = positions - np.min(positions) + 5
pos_bounded = np.zeros(num_frames, dtype=int)
curr = 32
for i, step in enumerate(macro_steps):
    curr += step
    if curr < 2: curr = 2
    if curr > 61: curr = 61
    pos_bounded[i] = curr

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/particle.mp4', fourcc, 30.0, (width, height), isColor=False)

for p in pos_bounded:
    frame = np.zeros((height, width), dtype=np.uint8)
    frame[32:34, p:p+2] = 255
    out.write(frame)

out.release()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
