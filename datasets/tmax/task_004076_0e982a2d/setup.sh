#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ libeigen3-dev ffmpeg
pip3 install pytest numpy matplotlib opencv-python-headless

mkdir -p /app

python3 << 'EOF'
import os
import numpy as np
import cv2

os.makedirs("/app/corpus/clean", exist_ok=True)
os.makedirs("/app/corpus/evil", exist_ok=True)

# Generate clean matrices
for i in range(20):
    A = np.random.randn(64, 64)
    U, S, V = np.linalg.svd(A)
    S = np.random.uniform(1, 10, 64)
    M = U @ np.diag(S) @ V
    np.savetxt(f"/app/corpus/clean/{i}.txt", M)

# Generate evil matrices
for i in range(20):
    A = np.random.randn(64, 64)
    U, S, V = np.linalg.svd(A)
    S = np.random.uniform(0, 1e-5, 64)
    S[0] = 1000
    M = U @ np.diag(S) @ V
    np.savetxt(f"/app/corpus/evil/{i}.txt", M)

# Generate video
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/fluid_flow.mp4', fourcc, 10.0, (64, 64))
for i in range(1, 101):
    frame = np.random.randint(0, 256, (64, 64, 3), dtype=np.uint8)
    if i in [15, 16, 17, 50, 85]:
        frame[6:58, 6:58] = 255
    out.write(frame)
out.release()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
