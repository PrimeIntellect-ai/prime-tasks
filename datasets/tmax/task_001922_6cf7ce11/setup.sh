#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy opencv-python-headless

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np
import cv2
import scipy.linalg

# Generate video
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/vibration_test.mp4', fourcc, 100.0, (128, 128), False)

x, y = np.meshgrid(np.linspace(-1, 1, 128), np.linspace(-1, 1, 128))
for i in range(100):
    t = i * 0.01
    cx = 0.5 * np.exp(-0.5*t) * np.cos(10.0*t)
    cy = 0.5 * np.exp(-1.0*t)
    frame = np.exp(-((x - cx)**2 + (y - cy)**2) / 0.1)
    frame = (frame * 255).astype(np.uint8)
    out.write(frame)
out.release()

# Generate clean matrices
for i in range(50):
    A = np.random.randn(50, 50)
    U, s, V = np.linalg.svd(A)
    s = np.linspace(1, 100, 50)
    A = U @ np.diag(s) @ V
    np.save(f'/app/corpus/clean/clean_{i}.npy', A)

# Generate evil matrices
for i in range(50):
    if i < 15:
        A = np.random.randn(50, 50)
        A[:, 0] = A[:, 1]
    elif i < 30:
        A = scipy.linalg.hilbert(50)
    elif i < 45:
        A = np.random.randn(50, 50)
        A[0, 0] = np.nan
    else:
        A = np.random.randn(50, 50)
        A[0, 0] = np.inf
    np.save(f'/app/corpus/evil/evil_{i}.npy', A)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
