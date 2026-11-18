#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr curl netcat-openbsd
pip3 install pytest Pillow pytesseract

mkdir -p /app
cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "DIAG_PORT_HTTP=9080\nDIAG_PORT_TCP=9081\nSECRET=BGP456"
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/network_diag_schematic.png')
EOF
python3 /tmp/gen_image.py
rm /tmp/gen_image.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
