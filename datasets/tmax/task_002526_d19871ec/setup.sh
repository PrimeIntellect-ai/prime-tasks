#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk socat netcat-openbsd ffmpeg
    pip3 install pytest numpy opencv-python-headless

    mkdir -p /app

    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np

raw_intensities = [200, 250, 300, 2, 400, 450, 500, 5, 600, 650, 700, 750, 800, 8, 900, 950, 850, 750, 650, 550]

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/telemetry.mp4', fourcc, 1.0, (100, 100), isColor=False)

for val in raw_intensities:
    pixel_val = int((val / 1000.0) * 255.0)
    frame = np.full((100, 100), pixel_val, dtype=np.uint8)
    out.write(frame)

out.release()
EOF

    python3 /tmp/generate_video.py
    rm /tmp/generate_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
