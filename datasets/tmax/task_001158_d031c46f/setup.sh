#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest Pillow

    mkdir -p /app
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color = (73, 109, 137))
d = ImageDraw.Draw(img)
d.text((10,10), "ROGUE SERVICE PORT: 8443", fill=(255,255,0))
img.save('/app/network_diagram.png')
EOF
    python3 /tmp/gen_image.py
    rm /tmp/gen_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
