#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app

    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np

secret = "S3cr3tK3y123!@#|<svg/onload=alert>"
bits = ''.join(format(ord(i), '08b') for i in secret)

out = cv2.VideoWriter('/app/attack_recording.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100))

for _ in range(20):
    out.write(np.random.randint(0, 255, (100, 100, 3), dtype=np.uint8))

blue_frame = np.zeros((100, 100, 3), dtype=np.uint8)
blue_frame[:] = [255, 0, 0] # BGR
out.write(blue_frame)

for bit in bits:
    color = 255 if bit == '1' else 0
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    frame[:] = [color, color, color]
    out.write(frame)

for _ in range(23):
    out.write(np.random.randint(0, 255, (100, 100, 3), dtype=np.uint8))

out.release()
EOF

    python3 /tmp/generate_video.py
    rm /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
