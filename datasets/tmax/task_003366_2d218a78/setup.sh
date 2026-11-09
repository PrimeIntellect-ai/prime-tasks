#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang fonts-liberation
pip3 install pytest Pillow

mkdir -p /app

cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw, ImageFont

img = Image.new('RGB', (400, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 24)
except IOError:
    font = ImageFont.load_default()

text = "RATE_LIMIT=4\nVALID_KEYS:\nomega\ntheta\nsigma\nlambda"
d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save('/app/config.png')
EOF

python3 /tmp/gen_img.py
rm /tmp/gen_img.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
