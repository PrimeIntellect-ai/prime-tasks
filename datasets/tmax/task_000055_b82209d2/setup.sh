#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6 libgl1-mesa-glx
    pip3 install pytest numpy scipy opencv-python-headless

    mkdir -p /app

    # Create oracle script
    cat << 'EOF' > /app/oracle_matrix_prep.py
import sys
import numpy as np

def process(filepath):
    A = np.loadtxt(filepath, delimiter=',')
    A_sym = (A + A.T) / 2.0
    w, v = np.linalg.eigh(A_sym)
    w_clipped = np.maximum(w, 1e-5)
    A_reg = v @ np.diag(w_clipped) @ v.T
    L = np.linalg.cholesky(A_reg)
    np.savetxt(sys.stdout, L, delimiter=',')

if __name__ == "__main__":
    process(sys.argv[1])
EOF

    # Generate synthetic video
    cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np

width, height = 200, 200
fps = 30
duration = 2
num_frames = fps * duration

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/particle_motion.mp4', fourcc, fps, (width, height), False)

pos = np.zeros((5, 2))
pos[:, 0] = width / 2
pos[:, 1] = height / 2

for i in range(num_frames):
    img = np.zeros((height, width), dtype=np.uint8)
    pos += np.random.randn(5, 2) * 2
    pos[:, 0] += np.random.randn() * 3
    pos[:, 1] += np.random.randn() * 3

    for p in pos:
        x, y = int(p[0]), int(p[1])
        if 0 <= x < width and 0 <= y < height:
            cv2.circle(img, (x, y), 2, 255, -1)

    out.write(img)

out.release()
EOF

    python3 /app/generate_video.py
    rm /app/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
