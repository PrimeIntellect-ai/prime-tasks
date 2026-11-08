#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-dejavu-core
    pip3 install pytest Pillow

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (800, 200), color='white')
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 40)
except:
    font = ImageFont.load_default()
d.text((20, 50), "c2VjcmV0X2FkbWluX3Rva2VuXzEyMw==", fill='black', font=font)
img.save('/app/admin_badge.png')
EOF
    python3 /tmp/gen_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
