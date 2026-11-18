#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        golang-go \
        fonts-dejavu-core

    pip3 install pytest pillow

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (800, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "BASELINE CONFIGURATION\nHostname: core-db-primary\nCores: 64\nMemory: 256\nStorage: NVMe"
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 32)
d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save('/app/config_baseline.png')
EOF
    python3 /tmp/gen_img.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
