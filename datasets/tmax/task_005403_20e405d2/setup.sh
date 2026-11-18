#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest numpy Pillow scipy scikit-learn opencv-python-headless

mkdir -p /app/corpus/clean /app/corpus/evil /tmp/video_frames

cat << 'EOF' > /tmp/gen.py
import numpy as np
from PIL import Image
import os

# Generate clean corpus
for i in range(20):
    img = np.random.randint(0, 256, (100, 100, 3), dtype=np.uint8)
    Image.fromarray(img).save(f'/app/corpus/clean/clean_{i:02d}.jpg')

# Generate evil corpus
for i in range(20):
    img = np.random.randint(0, 256, (100, 100, 3), dtype=np.uint8)
    img[:, :, 1] = 128  # low variance in green channel
    Image.fromarray(img).save(f'/app/corpus/evil/evil_{i:02d}.jpg')

# Generate video frames
for i in range(60):
    img = np.random.randint(0, 256, (100, 100, 3), dtype=np.uint8)
    if i % 5 == 0:
        img[:, :, 1] = 128
    Image.fromarray(img).save(f'/tmp/video_frames/frame_{i:03d}.jpg')
EOF

python3 /tmp/gen.py
ffmpeg -framerate 1 -i /tmp/video_frames/frame_%03d.jpg -c:v libx264 -pix_fmt yuv420p /app/conveyor.mp4
rm -rf /tmp/video_frames /tmp/gen.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
