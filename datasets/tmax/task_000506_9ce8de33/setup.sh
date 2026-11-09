#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        ffmpeg \
        libsm6 \
        libxext6 \
        libgl1-mesa-glx \
        zip \
        tar \
        cargo \
        rustc

    pip3 install pytest opencv-python-headless numpy

    mkdir -p /app/archives

    python3 -c "
import cv2
import numpy as np
import math
import os
import tarfile
import zipfile

# Generate video
out = cv2.VideoWriter('/app/stability.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 10, (200, 200))
for t in range(500):
    frame = np.zeros((200, 200, 3), dtype=np.uint8)
    if t == 342:
        y = 185
    else:
        y = int(100 + 80 * math.sin(t * 0.05))
        if y >= 185:
            y = 184
    frame[y:y+10, 100:110] = (255, 255, 255)
    out.write(frame)
out.release()

# Generate archives
for i in range(500):
    if i % 2 == 0:
        filename = 'config_A.conf.mod1'
        content = b'X' * 1000
    else:
        filename = 'config_B.conf.mod2'
        content = b'Y' * 1000

    with open(filename, 'wb') as f:
        f.write(content)

    with tarfile.open('payload.tar', 'w') as tar:
        tar.add(filename)

    with zipfile.ZipFile(f'/app/archives/rev_{i}.zip', 'w') as zipf:
        zipf.write('payload.tar')

    os.remove(filename)
os.remove('payload.tar')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
