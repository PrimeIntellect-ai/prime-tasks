#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr g++ fonts-dejavu-core
    pip3 install pytest Pillow

    mkdir -p /app
    cat << 'EOF' > /app/make_img.py
from PIL import Image, ImageDraw, ImageFont
text = """Weights:
1.5 -0.5 0.0
0.0 2.0 -1.0
Bias:
0.1 -0.5
Clamp:
-5.0 5.0"""
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
img = Image.new('RGB', (400, 300), color='white')
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill='black', font=font)
img.save('/app/transformation_rules.png')
EOF
    python3 /app/make_img.py
    rm /app/make_img.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
