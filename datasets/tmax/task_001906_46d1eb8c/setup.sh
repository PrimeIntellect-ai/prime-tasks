#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-opencv
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/sys_root

    # Generate the video and ground truth manifest
    cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np
import os

os.makedirs('/app', exist_ok=True)

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/deploy_logs.mp4', fourcc, 1.0, (800, 600))

text = """BEGIN_TX
ACTION: CREATE_FILE
PATH: test.txt
DATA: aGVsbG8=
END_TX"""

img = np.zeros((600, 800, 3), dtype=np.uint8)
y0, dy = 50, 30
for i, line in enumerate(text.split('\n')):
    y = y0 + i*dy
    cv2.putText(img, line, (50, y), cv2.FONT_HERSHEY_SIMPLEX, 1, (255,255,255), 2)

for _ in range(5):
    out.write(img)

out.release()

with open('/app/ground_truth_manifest.txt', 'w') as f:
    f.write("F test.txt 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824\n")
EOF

    python3 /tmp/gen_video.py
    rm /tmp/gen_video.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
