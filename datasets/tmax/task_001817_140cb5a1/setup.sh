#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk jq bc
    pip3 install pytest numpy opencv-python-headless scipy pandas

    mkdir -p /app
    cat << 'EOF' > /app/generate_data.py
import numpy as np
import cv2

# Generate Laplacian matrix
n = 10
L = np.diag(np.ones(n) * (n - 1)) - np.ones((n, n))
# Add slight truncation artifact
L = np.round(L, 5)
np.savetxt('/app/laplacian.csv', L, delimiter=',')

# Generate video
fps = 60
duration = 5
frames = fps * duration
width, height = 640, 480

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/membrane_vib.mp4', fourcc, fps, (width, height), False)

for i in range(frames):
    t = i / fps
    intensity = 127 + 100 * np.sin(2 * np.pi * 4.5 * t)
    frame = np.zeros((height, width), dtype=np.uint8)
    # central region x=270:370, y=190:290
    frame[190:290, 270:370] = int(np.clip(intensity, 0, 255))
    out.write(frame)

out.release()
EOF

    python3 /app/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
