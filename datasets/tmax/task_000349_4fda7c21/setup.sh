#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr nginx supervisor
    pip3 install pytest Flask Pillow

    mkdir -p /app
    cat << 'EOF' > /tmp/generate_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "SERVER CONFIGURATION\nIP: 192.168.1.100\nADMIN_TOKEN: 8xG2pL9\nSTARTUP: AUTOMATIC"
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/archived_record.png')
EOF
    python3 /tmp/generate_image.py
    rm /tmp/generate_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
