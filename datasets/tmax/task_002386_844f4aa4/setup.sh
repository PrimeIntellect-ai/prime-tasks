#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-liberation
    pip3 install pytest Pillow

    # Generate required files
    python3 -c '
import os
from PIL import Image, ImageDraw, ImageFont

os.makedirs("/app", exist_ok=True)

# Generate dump.bin
with open("/app/dump.bin", "wb") as f:
    f.write(b"A" * 32)
    f.write(b"B" * 1048576)
    f.write(b"C" * 1048576)
    f.write(b"D" * 500)

# Generate disk_warning.png
img = Image.new("RGB", (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 30)
except:
    font = ImageFont.load_default()
d.text((10, 10), "CRITICAL_VOL_8841", fill=(0, 0, 0), font=font)
img.save("/app/disk_warning.png")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
