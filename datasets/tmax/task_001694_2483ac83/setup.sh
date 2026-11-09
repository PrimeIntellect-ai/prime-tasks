#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-dejavu-core
    pip3 install pytest Pillow

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw, ImageFont
import os

img = Image.new('RGB', (400, 200), color='white')
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 32)
except:
    font = ImageFont.load_default()

text = "PORT: 9443\nTOKEN: SecureLogX99"
d.text((20, 40), text, fill='black', font=font)
img.save('/app/config_spec.png')
EOF
    python3 /tmp/gen_img.py
    rm /tmp/gen_img.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
