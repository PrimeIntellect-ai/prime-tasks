#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc libc6-dev
    pip3 install pytest Pillow numpy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
from PIL import Image, ImageDraw

img = Image.new('RGB', (400, 150), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "DIM1_MEAN=10.0 DIM1_STD=2.5\nDIM2_MEAN=-5.5 DIM2_STD=1.2\nDIM3_MEAN=3.14 DIM3_STD=0.5"
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/thresholds.png')

means = np.array([10.0, -5.5, 3.14])
stds = np.array([2.5, 1.2, 0.5])

for i in range(15):
    data = np.random.randn(100, 3) * stds + means
    np.savetxt(f'/app/corpus/clean/clean_{i}.csv', data, delimiter=',', fmt='%.6f')

for i in range(15):
    data = np.random.randn(100, 3) * stds + means + stds * 5
    np.savetxt(f'/app/corpus/evil/evil_{i}.csv', data, delimiter=',', fmt='%.6f')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
