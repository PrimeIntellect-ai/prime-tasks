#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        make \
        tesseract-ocr \
        curl \
        netcat-openbsd \
        libmicrohttpd-dev \
        libssl-dev \
        libjansson-dev

    pip3 install pytest Pillow

    mkdir -p /app
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), 'SuperSecretP4ss!', fill=(0, 0, 0))
img.save('/app/evidence.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
