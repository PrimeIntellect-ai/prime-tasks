#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = 'Staged Rollout Config v2.1\nProxy Port: 8088\nRoute to: 127.0.0.1:9099\nSecret Key: R0ll0ut_S3cr3t'
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/architecture.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
