#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg g++
pip3 install pytest pandas numpy opencv-python-headless

mkdir -p /app
mkdir -p /home/user/frames

cat << 'EOF' > /tmp/gen_data.py
import cv2
import numpy as np

out = cv2.VideoWriter('/app/radar_scan.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100), isColor=False)
for i in range(100):
    frame = np.zeros((100, 100), dtype=np.uint8)
    angle = i * (2 * np.pi / 100)
    x = int(50 + 30 * np.cos(angle))
    y = int(50 + 30 * np.sin(angle))
    frame[max(0, y-2):min(100, y+3), max(0, x-2):min(100, x+3)] = 255
    out.write(frame)
out.release()

with open('/app/sensor_meta.txt', 'w') as f:
    for i in range(100):
        t = i * 100
        f.write(f"[VALID] T:{t} S:ACTIVE\n")
        if i % 5 == 0:
            f.write(f"[INVALID] T:{t+50} S:OFF\n")
EOF

python3 /tmp/gen_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
