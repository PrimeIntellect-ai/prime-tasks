#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libglib2.0-0
    pip3 install pytest numpy opencv-python-headless scipy flask requests

    # Generate the oscillator video
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np
import math
import os

os.makedirs('/app', exist_ok=True)

width, height = 640, 480
fps = 30
duration = 5.0 # seconds
frames = int(fps * duration)

omega_n = 2.0
zeta = 0.1
omega_d = omega_n * math.sqrt(1 - zeta**2)
x0 = 200.0

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/oscillator.mp4', fourcc, fps, (width, height))

for i in range(frames):
    t = i / fps
    displacement = math.exp(-zeta * omega_n * t) * x0 * math.cos(omega_d * t)
    x_pos = int(320 + displacement)

    frame = np.zeros((height, width, 3), dtype=np.uint8)

    # Draw white square 10x10
    top_left = (x_pos - 5, 240 - 5)
    bottom_right = (x_pos + 5, 240 + 5)
    cv2.rectangle(frame, top_left, bottom_right, (255, 255, 255), -1)

    out.write(frame)

out.release()
EOF

    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/workspace
    chmod -R 777 /home/user
    chmod -R 777 /app
