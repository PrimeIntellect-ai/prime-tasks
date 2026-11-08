#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6
    pip3 install pytest opencv-python-headless scikit-image numpy

    mkdir -p /app

    # Generate a dummy video file
    python3 -c "
import cv2
import numpy as np

out = cv2.VideoWriter('/app/surveillance.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
for i in range(150):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    cv2.putText(frame, f'Frame {i}', (50, 50), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
    out.write(frame)
out.release()
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
