#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        cmake \
        make \
        ffmpeg \
        tesseract-ocr \
        libtesseract-dev \
        wget \
        curl \
        nlohmann-json3-dev \
        libcpp-httplib-dev

    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app

    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np
import os

out = cv2.VideoWriter('/app/backup_monitor_incident.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1, (800, 480))
texts = [
    "Job: A | DependsOn: NONE | Size: 100",
    "Job: B | DependsOn: A | Size: 200",
    "Job: C | DependsOn: A | Size: 150",
    "Job: D | DependsOn: B | Size: 300\nJob: D | DependsOn: C | Size: 300",
    "Job: D | DependsOn: B | Size: 300\nJob: D | DependsOn: C | Size: 300\nJob: D | DependsOn: B | Size: 300",
    "Job: E | DependsOn: D | Size: 500"
]

for t in texts:
    img = np.zeros((480, 800, 3), dtype=np.uint8)
    y0, dy = 50, 40
    for i, line in enumerate(t.split('\n')):
        y = y0 + i*dy
        cv2.putText(img, line, (20, y), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
    out.write(img)

out.release()
EOF

    python3 /tmp/generate_video.py
    rm /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
