#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc tesseract-ocr python3-pil
pip3 install pytest

mkdir -p /app
python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (500, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = 'MOCK ENVIRONMENT SPECS:\nLISTEN_PORT: 8088\nSERVICE_ID: TKN-9942-ALPHA'
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/authz_spec.png')
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
