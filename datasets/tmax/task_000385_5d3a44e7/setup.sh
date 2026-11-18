#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tesseract-ocr python3-pil
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw

img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "SYSTEM MANIFEST\nAuthToken: Z98-KML-001\nTarget: prod-db-primary\nDate: 1999-10-24"
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/legacy_route_manifest.png')
EOF

    python3 /tmp/gen_image.py
    rm /tmp/gen_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
