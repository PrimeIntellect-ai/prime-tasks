#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg libsm6 libxext6
    pip3 install pytest kuzu opencv-python Pillow pandas

    mkdir -p /app/corpus/evil /app/corpus/clean

    python3 -c "
import cv2
import numpy as np
import os

# Generate Video
out = cv2.VideoWriter('/app/network_capture.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (100, 100))
for i in range(30):
    frame = np.zeros((100, 100, 3), dtype=np.uint8)
    if i < 14:
        frame[0, 0] = [0, 0, 255] # BGR format: Red is (0, 0, 255)
    out.write(frame)
out.release()

# Generate CSVs
for i in range(20):
    with open(f'/app/corpus/evil/evil_{i}.csv', 'w') as f:
        f.write('source,target,relation\n')
        for b in range(14):
            f.write(f'master,bot_{b},COMMAND\n')
            f.write(f'bot_{b},target,ATTACK\n')

for i in range(20):
    with open(f'/app/corpus/clean/clean_{i}.csv', 'w') as f:
        f.write('source,target,relation\n')
        for b in range(13):
            f.write(f'master,bot_{b},COMMAND\n')
            f.write(f'bot_{b},target,ATTACK\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
