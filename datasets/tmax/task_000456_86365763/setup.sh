#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr cargo rustc gzip
    pip3 install pytest Pillow

    # Create app directory
    mkdir -p /app

    # Generate blueprint image using Pillow
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (500, 200), color='white')
d = ImageDraw.Draw(img)
text = 'SYSTEM CONFIGURATION - CLASSIFIED\nAPI_TOKEN=AlphaBravoCharlie99\nPORT=8118'
d.text((10, 10), text, fill='black')
img.save('/app/blueprint.png')
"

    # Create legacy configs
    mkdir -p /app/legacy_configs
    echo '{"service_name":"auth_svc","version":2,"settings":{}}' | gzip > /app/legacy_configs/file1.gz
    echo '{"service_name":"payment_gw","version":1,"settings":{}}' | gzip > /app/legacy_configs/file2.gz

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
