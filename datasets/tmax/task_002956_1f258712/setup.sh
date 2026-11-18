#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-liberation
    pip3 install pytest Pillow

    mkdir -p /app
    cat << 'EOF' > /app/generate_image.py
from PIL import Image, ImageDraw, ImageFont

img = Image.new('RGB', (800, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf", 20)
except IOError:
    font = ImageFont.load_default()

text = """Node: Employee | id: E101, name: "Alice Smith"
Node: Employee | id: E102, name: "Bob Jones"
Node: Project | id: P99, name: "Project Titan"
Node: Project | id: P42, name: "Project Apollo"
Edge: WORKS_ON | from: E101, to: P99
Edge: WORKS_ON | from: E101, to: P42
Edge: WORKS_ON | from: E102, to: P99"""

d.text((10, 10), text, fill=(0, 0, 0), font=font)
img.save('/app/legacy_export.png')
EOF

    python3 /app/generate_image.py
    rm /app/generate_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
