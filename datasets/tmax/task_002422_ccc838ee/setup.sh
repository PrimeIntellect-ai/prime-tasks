#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    cat << 'EOF' > /tmp/generate.py
import os
from PIL import Image, ImageDraw
import random

os.makedirs('/app/corpus/evil', exist_ok=True)
os.makedirs('/app/corpus/clean', exist_ok=True)

# Generate evidence image
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
# Draw text large enough for tesseract to read easily
d.text((50, 40), "SEED: 8x9F2a_poly", fill=(0, 0, 0))
img.save('/app/evidence.png')

# Generate clean images
for i in range(50):
    img = Image.new('RGB', (10, 10), color=(random.randint(0,255), random.randint(0,255), random.randint(0,255)))
    img.save(f'/app/corpus/clean/clean_{i}.png')

# Generate evil images
payloads = [b'\x7fELF', b'../../../../etc/shadow', b'<script>alert(1)</script>']
for i in range(50):
    img_path = f'/app/corpus/evil/evil_{i}.png'
    img = Image.new('RGB', (10, 10), color=(random.randint(0,255), random.randint(0,255), random.randint(0,255)))
    img.save(img_path)
    # Append payload to the end of the PNG file
    with open(img_path, 'ab') as f:
        f.write(random.choice(payloads))
EOF

    python3 /tmp/generate.py
    rm /tmp/generate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
