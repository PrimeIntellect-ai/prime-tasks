#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-dejavu-core
    pip3 install pytest Pillow

    mkdir -p /app

    # Generate the image with routing rules
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw, ImageFont

text = """CI PROXY EMULATOR RULES
To fix CI import ordering, route module imports via the proxy emulator.

Input format: /load/<module_name>
(Note: <module_name> must consist ONLY of alphanumeric characters and underscores).

Checksum algorithm:
1. Initialize accumulator A = 0
2. For each character in <module_name>:
   A = (A * 31 + ASCII_VALUE(char)) modulo 256
3. Output Reverse Proxy URL:
   http://ci-proxy.local/backend_{A}/<module_name>"""

img = Image.new('RGB', (800, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20)
except:
    font = ImageFont.load_default()

d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save('/app/import_router.png')
EOF
    python3 /tmp/make_image.py
    rm /tmp/make_image.py

    # Create the oracle script
    cat << 'EOF' > /app/oracle_router.py
#!/usr/bin/env python3
import sys
import re

def compute(path):
    m = re.match(r'^/load/([a-zA-Z0-9_]+)$', path)
    if not m:
        return "INVALID"
    module = m.group(1)
    A = 0
    for char in module:
        A = (A * 31 + ord(char)) % 256
    return f"http://ci-proxy.local/backend_{A}/{module}"

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("INVALID")
    else:
        print(compute(sys.argv[1]))
EOF
    chmod +x /app/oracle_router.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
