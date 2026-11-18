#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tesseract-ocr
    pip3 install pytest pandas numpy pillow

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (600, 400), color='white')
d = ImageDraw.Draw(img)
text = """Historical Prior Parameters
Feature Means:
[ 1.50, -2.00, 3.50 ]

Covariance Matrix:
[  2.00   0.40  -0.30 ]
[  0.40   1.50   0.20 ]
[ -0.30   0.20   3.00 ]"""
d.text((10,10), text, fill='black')
img.save('/app/legacy_report.png')
EOF
    python3 /tmp/gen_img.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data_gen
    chmod -R 777 /home/user
    chmod -R 777 /app
