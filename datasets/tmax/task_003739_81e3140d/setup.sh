#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install --no-cache-dir pytest Pillow numpy scipy fastapi uvicorn requests
    pip3 install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu

    mkdir -p /app

    cat << 'EOF' > /tmp/make_image.py
import os
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "Model Specifications\nHidden Layers: 128, 64\nDistribution Mean: 3.5\nDistribution Std: 0.8"
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/spec.png')
EOF
    python3 /tmp/make_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
