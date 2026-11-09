#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr cargo rustc
pip3 install pytest pillow

python3 -c "
import os
from PIL import Image, ImageDraw

os.makedirs('/app', exist_ok=True)

# Generate image
img = Image.new('RGB', (400, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'MAX_LEN: 40\nREQUIRED_TOKEN: {user}', fill=(0,0,0))
img.save('/app/ui_spec.png')

# Generate CP1252 bin file (writing bytes directly to avoid UnicodeEncodeError)
content = b'msg_welcome=Welcome back, {user}!\nmsg_error=An error occurred for {user}. Please contact support immediately since this string is too long.\nmsg_short=Hi there!\nmsg_french=Bonjour {user}, le caf\xe9 co\xfbte 5\x80.'
with open('/app/raw_locales.bin', 'wb') as f:
    f.write(content)
"

chmod -R 777 /app

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
