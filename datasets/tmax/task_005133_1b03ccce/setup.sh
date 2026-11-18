#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest fastapi uvicorn opencv-python-headless numpy requests

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/video.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
for i in range(100):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    x = i * 5
    cv2.rectangle(frame, (x, 200), (x+50, 250), (255, 255, 255), -1)
    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/tests
    chmod -R 777 /home/user
