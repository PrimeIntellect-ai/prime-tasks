#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr g++ fonts-liberation
    pip3 install pytest Pillow

    mkdir -p /app
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (400, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    fnt = ImageFont.truetype('/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf', 24)
except:
    fnt = ImageFont.load_default()
text = '''Edges:
0 1
1 2
2 0
2 3
3 3
Alpha: 0.15'''
d.text((10, 10), text, font=fnt, fill=(0, 0, 0))
img.save('/app/network_params.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
