#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest numpy imageio imageio[ffmpeg]

mkdir -p /app
cat << 'EOF' > /tmp/generate_video.py
import numpy as np
import imageio.v2 as imageio

frames = []
# Phase 1: Small square moving
for i in range(20):
    frame = np.zeros((64, 64), dtype=np.uint8)
    frame[30:34, 10+i*2:14+i*2] = 255
    frames.append(frame)
# Phase 2: Square expands
for i in range(20):
    frame = np.zeros((64, 64), dtype=np.uint8)
    frame[30-i:34+i, 30:34+i] = 255
    frames.append(frame)
# Phase 3: Fades out
for i in range(20):
    frame = np.zeros((64, 64), dtype=np.uint8)
    val = max(0, 255 - i*12)
    frame[10:54, 30:54] = val
    frames.append(frame)

imageio.mimwrite('/app/experiment_record.mp4', frames, fps=1)
EOF
python3 /tmp/generate_video.py
chmod 644 /app/experiment_record.mp4

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
