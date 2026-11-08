#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg python3-opencv
    pip3 install pytest

    mkdir -p /app

    # Generate the video with exactly 5 red frames
    cat << 'EOF' > /tmp/gen_vid.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/server_status.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 30, (64, 64))
for i in range(60):
    frame = np.zeros((64, 64, 3), dtype=np.uint8)
    # OpenCV uses BGR format
    if i in [10, 20, 30, 40, 50]:
        frame[:, :] = [0, 0, 255]
    out.write(frame)
out.release()
EOF
    python3 /tmp/gen_vid.py

    # Create oracle script
    cat << 'EOF' > /app/oracle_filter
#!/usr/bin/env python3
import sys
data = sys.stdin.read()
if data.count("ERROR") > 5:
    print("ALERT")
else:
    print("OK")
EOF
    chmod +x /app/oracle_filter

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
