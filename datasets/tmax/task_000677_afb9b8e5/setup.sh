#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev zlib1g-dev tesseract-ocr netcat-openbsd
    pip3 install pytest Pillow

    mkdir -p /app/data

    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (300, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'BKP-8821-X9', fill=(0,0,0))
img.save('/app/auth_badge.png')
"

    echo "USER=admin ACTION=login STATUS=success SECRET_TOKEN=x9A4b2C1 details=none" > /app/data/log1.log
    echo "Padding padding padding padding padding padding padding" >> /app/data/log1.log

    echo "rotating..." > /app/data/log2.log

    echo "USER=guest ACTION=logout SECRET_TOKEN=99zzAA11 and another SECRET_TOKEN=00000000" > /app/data/log3.log
    echo "More padding to ensure the file is larger than 50 bytes." >> /app/data/log3.log

    echo "SECRET_TOKEN=12345678" > /app/data/config.txt
    echo "Padding padding padding padding padding padding padding" >> /app/data/config.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
