#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc python3-opencv socat curl
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/trajectory.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1, (1000, 1000))
for i in range(20):
    frame = np.zeros((1000, 1000, 3), dtype=np.uint8)
    x = i
    y = 2 * (x * x) - 3 * x + 5
    if 0 <= x < 1000 and 0 <= y < 1000:
        frame[y, x] = (255, 255, 255)
    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
