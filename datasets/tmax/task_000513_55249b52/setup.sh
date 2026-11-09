#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo libssl-dev pkg-config ffmpeg
    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/dashboard_capture.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (640, 480))
for i in range(300):
    img = np.zeros((480, 640, 3), dtype=np.uint8)
    if i == 150:
        cv2.putText(img, "ELF Headers Analyzed. Target Port: 8443.", (10, 50), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
        cv2.putText(img, "Expected CN: c2.malicious-domain.local.", (10, 100), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
        cv2.putText(img, "Knock: a1b2c3d4e5f67890a1b2c3d4e5f67890", (10, 150), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
    out.write(img)
out.release()
EOF
    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
