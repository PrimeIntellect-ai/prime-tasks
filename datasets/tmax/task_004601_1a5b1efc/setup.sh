#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr

    pip3 install pytest Pillow flask pyjwt requests

    mkdir -p /app
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,50), 'System Architecture... Notes: ISSUER_ID: DEVSEC-CORP-77X ... End of diagram.', fill=(0,0,0))
img.save('/app/diagram.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
