#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr netcat-openbsd gawk bc fonts-liberation
pip3 install pytest pillow

mkdir -p /app
python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf', 48)
except Exception:
    font = ImageFont.load_default()
d.text((20, 70), 'COEFFICIENTS: ALPHA=3.5 BETA=1.2', fill=(0,0,0), font=font)
img.save('/app/system_params.png')
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
