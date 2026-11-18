#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make tesseract-ocr libtesseract-dev curl
    pip3 install pytest Pillow

    mkdir -p /app

    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (200, 200), color='white')
d = ImageDraw.Draw(img)
text = "A->B\nB->C\nC->D\nA->E\nE->D\nD->F\nB->F"
d.text((10,10), text, fill='black')
img.save('/app/topology.png')
EOF

    python3 /tmp/make_image.py
    rm /tmp/make_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
