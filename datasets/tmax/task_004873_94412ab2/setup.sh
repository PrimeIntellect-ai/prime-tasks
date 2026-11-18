#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr rustc cargo
    pip3 install pytest Pillow

    mkdir -p /app

    # Generate the architecture diagram image using Python and Pillow
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (600, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = '''Migration Target Setup:
Hostname: gateway.internal.cloud
Port: 8222
RejectionCode: ERR_KEY_SILENT_DROP_99x'''
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/arch.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
