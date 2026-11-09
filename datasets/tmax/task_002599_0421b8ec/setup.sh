#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr rustc cargo curl build-essential
    pip3 install pytest numpy Pillow

    mkdir -p /app

    python3 -c "
import numpy as np
from PIL import Image, ImageDraw
import os

os.makedirs('/app', exist_ok=True)

# Generate image
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), 'CALIBRATION_TOKEN=XY88-SPEC-9Z', fill=(0, 0, 0))
img.save('/app/spectroscopy_meta.png')

# Generate CSV
np.random.seed(42)
x = np.linspace(10, 90, 100)
# Gaussian peak at 50.0 + noise
y = 20.0 * np.exp(-((x - 50.0)**2) / (2 * 5.0**2)) + np.random.normal(0, 2.0, 100)

with open('/app/raw_spectrum.csv', 'w') as f:
    f.write('x,y\n')
    for xi, yi in zip(x, y):
        f.write(f'{xi:.4f},{yi:.4f}\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
