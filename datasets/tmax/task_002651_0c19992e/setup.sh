#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        build-essential \
        python3-pil \
        fonts-liberation

    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/generate_image.py
from PIL import Image, ImageDraw, ImageFont

text = """Time  Sensor_Y
0     10.0
1     12.0
2     ----
3     16.0
4     18.0
5     #ERR
6     22.0
7     24.0
8     ??.?
9     28.0
10    30.0"""

font_path = "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf"
try:
    font = ImageFont.truetype(font_path, 24)
except Exception:
    font = ImageFont.load_default()

img = Image.new('RGB', (300, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save('/app/data_table.png')
EOF

    python3 /tmp/generate_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
