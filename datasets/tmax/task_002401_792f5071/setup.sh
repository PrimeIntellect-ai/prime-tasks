#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc fonts-liberation
    pip3 install pytest Pillow

    mkdir -p /app

    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (1200, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
font = ImageFont.truetype('/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf', 18)
d.text((10,10), 'RVhQTE9JVF9UT0tFTjpTRUMtOTk4ODc3NjZ8SEFTSDoxZDc3YmU0ZDIxNDMzMjBlZDRhNmFlOGI0N2UyYTdkMWQwNjg4MmZhODQ3NTc0NGVlMjY0ODUyMzFlNDM2MzRl', font=font, fill=(0,0,0))
img.save('/app/suspicious_login.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
