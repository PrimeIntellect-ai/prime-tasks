#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libgl1 libglib2.0-0
    pip3 install pytest opencv-python-headless grpcio grpcio-tools protobuf numpy

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

# BGR colors for OpenCV
colors = [
    (0, 0, 255),    # Red
    (0, 255, 0),    # Green
    (255, 0, 0),    # Blue
    (255, 255, 0),  # Cyan
    (0, 0, 255),    # Red
    (0, 255, 0),    # Green
    (0, 0, 255),    # Red
    (255, 0, 0),    # Blue
    (255, 0, 0),    # Blue
    (255, 255, 0),  # Cyan
    (0, 0, 0)       # Black
]

out = cv2.VideoWriter('/app/ci_test_run.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (100, 100))
for color in colors:
    frame = np.full((100, 100, 3), color, dtype=np.uint8)
    for _ in range(30):
        out.write(frame)
out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
