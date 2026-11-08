#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app/corpus/clean /app/corpus/evil /app/secret_eval/clean /app/secret_eval/evil

    cat << 'EOF' > /tmp/generate_data.py
import cv2
import numpy as np
import os

def create_dir(p):
    os.makedirs(p, exist_ok=True)

# Generate clean images (gradient or random shapes to avoid pure noise)
for i in range(50):
    img = np.zeros((100, 100, 3), dtype=np.uint8)
    cv2.rectangle(img, (10, 10), (90, 90), (100 + i*2, 50 + i*3, 200 - i), -1)
    cv2.imwrite(f'/app/corpus/clean/img_{i}.jpg', img)
    cv2.imwrite(f'/app/secret_eval/clean/img_{i}.jpg', img)

# Generate evil images (black or pure noise)
for i in range(50):
    if i % 2 == 0:
        img = np.zeros((100, 100, 3), dtype=np.uint8)
    else:
        img = np.random.randint(0, 255, (100, 100, 3), dtype=np.uint8) # pure noise
    cv2.imwrite(f'/app/corpus/evil/img_{i}.jpg', img)
    cv2.imwrite(f'/app/secret_eval/evil/img_{i}.jpg', img)

# Generate video
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/experiment_video.mp4', fourcc, 1.0, (100, 100))
for i in range(60):
    if 21 <= i <= 30: # Frames 22-31 (0-indexed: 21-30)
        frame = np.zeros((100, 100, 3), dtype=np.uint8)
    else:
        frame = np.zeros((100, 100, 3), dtype=np.uint8)
        cv2.circle(frame, (50, 50), 30, (150, 200, 100), -1)
    out.write(frame)
out.release()
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
