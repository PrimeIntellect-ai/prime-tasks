#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        qemu-utils \
        tesseract-ocr \
        fonts-liberation

    pip3 install pytest Pillow pytesseract

    mkdir -p /app

    # Generate the dashboard image
    python3 -c '
from PIL import Image, ImageDraw, ImageFont
img = Image.new("RGB", (800, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 32)
except IOError:
    font = ImageFont.load_default()
text = "STORAGE POLICY DASHBOARD\nAlerts: Active\nMax Utilization Threshold: 81.4%\nAction: Isolate unoptimized volumes."
d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save("/app/dashboard.png")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
