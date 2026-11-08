#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr socat nmap openssl
    pip3 install pytest Pillow

    mkdir -p /app

    # Generate the network topology image with the required text
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (600, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((50, 50), 'Confidential - Token: SecOps-99A2-XYZ', fill=(0, 0, 0))
img.save('/app/network_topology.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
