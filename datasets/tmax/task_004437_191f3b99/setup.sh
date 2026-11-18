#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc fonts-dejavu-core
    pip3 install pytest Pillow

    mkdir -p /app/data
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw, ImageFont

img = Image.new('RGB', (400, 100), color='white')
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 48)
except Exception:
    font = ImageFont.load_default()

d.text((50, 25), "5 12 7 2", fill='black', font=font)
img.save('/app/data/config_scan.png')
EOF
    python3 /tmp/gen_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
