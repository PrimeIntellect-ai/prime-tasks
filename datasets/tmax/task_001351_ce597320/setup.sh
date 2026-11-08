#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tesseract-ocr cargo
    pip3 install pytest pillow numpy

    cat << 'EOF' > /tmp/setup.py
import os
import json
import numpy as np
from PIL import Image, ImageDraw

# Create image
os.makedirs('/app', exist_ok=True)
img = Image.new('RGB', (200, 50), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), "THRESHOLD = 4.25", fill=(0,0,0))
img.save('/app/threshold.png')

# Create corpora
os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

np.random.seed(42)
for i in range(10):
    # Clean: normally distributed, capped to avoid random outliers > 4.25
    vals = np.clip(np.random.normal(0, 1, 100), -3.5, 3.5).tolist()
    with open(f'/app/corpus/clean/sim_{i}.json', 'w') as f:
        json.dump({"time": list(range(100)), "values": vals}, f)

for i in range(10):
    # Evil: normally distributed, with one outlier > 4.25
    vals = np.clip(np.random.normal(0, 1, 100), -3.5, 3.5).tolist()
    vals[50] = 6.0 # Definitely > 4.25 Z-score
    with open(f'/app/corpus/evil/sim_{i}.json', 'w') as f:
        json.dump({"time": list(range(100)), "values": vals}, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
