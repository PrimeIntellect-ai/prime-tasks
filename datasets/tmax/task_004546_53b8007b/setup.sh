#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        gcc \
        curl

    pip3 install pytest pillow numpy flask requests

    mkdir -p /app

    python3 -c "
from PIL import Image, ImageDraw
import os
os.makedirs('/app', exist_ok=True)
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = 'Monte Carlo Parameters:\nSeed Offset: 42042\nDrift: 0.05\nVolatility: 0.20'
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/schematic.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
