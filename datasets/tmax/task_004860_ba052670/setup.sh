#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc build-essential libglib2.0-0
pip3 install pytest numpy opencv-python-headless scipy

mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

cat << 'EOF' > /tmp/setup.py
import numpy as np
import cv2
import os

# Generate video
k = 0.45
c = 0.15
dt = 0.1
frames = 50

A = 255.0
B = 0.0

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/reaction_video.mp4', fourcc, 10.0, (200, 100))

for i in range(frames):
    frame = np.zeros((100, 200, 3), dtype=np.uint8)
    frame[:, :100, 2] = int(max(0, min(255, A)))  # Red channel for Left (A)
    frame[:, 100:, 2] = int(max(0, min(255, B)))  # Red channel for Right (B)
    out.write(frame)

    dA = -k * A + c * B
    dB = k * A - c * B
    A += dA * dt
    B += dB * dt

out.release()

# Generate clean corpus (stable for dt=0.1)
np.random.seed(42)
for i in range(10):
    N = 5
    M = np.random.rand(N, N) * 0.1
    for j in range(N):
        M[j, j] = -np.sum(M[j, :]) - 0.1
    with open(f'/app/corpus/clean/clean_{i}.txt', 'w') as f:
        f.write(f'{N}\n')
        np.savetxt(f, M, fmt='%.6f')

# Generate evil corpus (unstable for dt=0.1)
for i in range(10):
    N = 5
    M = np.random.rand(N, N) * 10.0
    for j in range(N):
        M[j, j] = np.sum(M[j, :]) + 20.0 # Positive eigenvalues -> explosive
    with open(f'/app/corpus/evil/evil_{i}.txt', 'w') as f:
        f.write(f'{N}\n')
        np.savetxt(f, M, fmt='%.6f')

EOF

python3 /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
