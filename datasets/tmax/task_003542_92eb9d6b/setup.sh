#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy opencv-python-headless fastapi uvicorn flask requests scipy

    mkdir -p /app
    cat << 'EOF' > /tmp/setup.py
import os
import cv2
import numpy as np

os.makedirs('/app', exist_ok=True)

fps = 30
duration = 10
frames = fps * duration
freq = 3.5
width, height = 200, 100

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/vibration.mp4', fourcc, fps, (width, height))

x_true = []
for i in range(frames):
    t = i / fps
    x = 100 + 40 * np.sin(2 * np.pi * freq * t)
    y = 50
    x_true.append(x)

    frame = np.zeros((height, width, 3), dtype=np.uint8)
    noise = np.random.randint(0, 50, (height, width, 3), dtype=np.uint8)
    frame = cv2.add(frame, noise)

    cv2.circle(frame, (int(x), int(y)), 5, (255, 255, 255), -1)
    out.write(frame)

out.release()

x_ref = np.array(x_true) + np.random.normal(0, 1.5, frames)
np.savetxt('/app/reference_signal.csv', x_ref, delimiter=',')
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
