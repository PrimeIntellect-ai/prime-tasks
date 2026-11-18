#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr nginx
    pip3 install pytest Pillow

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    python3 << 'EOF'
import os
from PIL import Image, ImageDraw

# Create image
img = Image.new('RGB', (200, 50), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "Threshold: 42.5", fill=(0, 0, 0))
img.save('/app/spec.png')

# Create clean corpus (instability < 42.5)
for i in range(5):
    with open(f'/app/corpora/clean/file_{i}.txt', 'w') as f:
        f.write("1.0\n10.0\n20.0\n30.0\n") # diff is 9+10+10 = 29

# Create evil corpus (instability >= 42.5)
for i in range(5):
    with open(f'/app/corpora/evil/file_{i}.txt', 'w') as f:
        f.write("1.0\n50.0\n100.0\n") # diff is 49+50 = 99
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
