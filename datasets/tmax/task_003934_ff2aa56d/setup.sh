#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        tesseract-ocr-eng \
        fonts-dejavu-core

    pip3 install pytest Pillow

    mkdir -p /app

    cat << 'EOF' > /app/oracle.py
import sys

for line in sys.stdin:
    line = line.split(';')[0]
    line = line.strip()
    if not line:
        continue
    if line == 'G28':
        print('G28 X Y')
        continue

    parts = line.split()
    if parts and parts[0] == 'M104':
        new_parts = []
        for p in parts:
            if p.startswith('S'):
                try:
                    val = int(p[1:])
                    if val > 240:
                        p = 'S240'
                except:
                    pass
            new_parts.append(p)
        print(' '.join(new_parts))
    elif parts and parts[0] == 'G1':
        new_parts = []
        for p in parts:
            if p.startswith('F'):
                try:
                    val = int(p[1:])
                    if val > 3600:
                        p = 'F3600'
                except:
                    pass
            new_parts.append(p)
        print(' '.join(new_parts))
    else:
        print(line)
EOF

    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw, ImageFont

text = """GCode Processing Rules:
- Remove any semicolon (;) and all text after it on the same line.
- Strip leading and trailing whitespace.
- Ignore completely empty lines (do not print them).
- If the line is exactly 'G28', change it to 'G28 X Y'.
- For 'M104' commands, if there is an 'S' parameter with an integer value strictly greater than 240, change it to 'S240'. If modified, ensure components are separated by exactly one space.
- For 'G1' commands, if there is an 'F' parameter with an integer value strictly greater than 3600, change it to 'F3600'. If modified, ensure components are separated by exactly one space."""

img = Image.new('RGB', (1200, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
except:
    font = ImageFont.load_default()
d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save('/app/processing_rules.png')
EOF

    python3 /tmp/make_image.py
    rm /tmp/make_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
