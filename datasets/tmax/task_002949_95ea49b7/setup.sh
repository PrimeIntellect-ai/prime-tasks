#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app/corpus/evil /app/corpus/clean

    cat << 'EOF' > /tmp/generate_data.py
import cv2
import numpy as np
import os

def create_frame(glitch=False, offset=0):
    # Grayscale grid
    frame = np.zeros((256, 256, 3), dtype=np.uint8)
    for i in range(0, 256, 32):
        cv2.line(frame, (i + offset % 32, 0), (i + offset % 32, 255), (128, 128, 128), 1)
        cv2.line(frame, (0, i + offset % 32), (255, i + offset % 32), (128, 128, 128), 1)

    if glitch:
        # Add red band (BGR format)
        y = np.random.randint(0, 200)
        h = np.random.randint(10, 50)
        frame[y:y+h, :, :] = [0, 0, 255]
    return frame

# Generate video
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/simulation_run.mp4', fourcc, 10.0, (256, 256))
for i in range(60):
    glitch = i in [15, 30, 45]
    frame = create_frame(glitch, i*2)
    out.write(frame)
out.release()

# Generate clean corpus
for i in range(50):
    frame = create_frame(glitch=False, offset=i*5)
    cv2.imwrite(f'/app/corpus/clean/frame_{i:03d}.png', frame)

# Generate evil corpus
for i in range(50):
    frame = create_frame(glitch=True, offset=i*5)
    cv2.imwrite(f'/app/corpus/evil/frame_{i:03d}.png', frame)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
