#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-dejavu-core
pip3 install pytest Pillow

mkdir -p /app
python3 -c '
from PIL import Image, ImageDraw, ImageFont
img = Image.new("RGB", (600, 100), color="white")
d = ImageDraw.Draw(img)
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 40)
d.text((10,10), "DEPLOY_SECRET_99X", fill="black", font=font)
img.save("/app/auth_token.png")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
