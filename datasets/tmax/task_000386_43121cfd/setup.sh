#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        libtesseract-dev \
        fonts-liberation

    pip3 install pytest Pillow requests

    # Create the specification image
    mkdir -p /app
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw, ImageFont
import os

text = """RetroAPI Spec V1
Endpoint: POST /run
Payload: {"asm": "instruction\\ninstruction..."}
Rate Limit: 20 requests per second per IP. 

Instruction Set:
LOAD reg val  (Sets reg to integer val)
ADD reg1 reg2 (Adds reg2 to reg1, stores in reg1)
SUB reg1 reg2 (Subtracts reg2 from reg1, stores in reg1)
MUL reg1 reg2 (Multiplies reg1 by reg2, stores in reg1)

Registers: r0, r1, r2, r3
All registers initialize to 0."""

img = Image.new('RGB', (800, 600), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf", 20)
except Exception:
    font = None

d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save("/app/arch.png")
EOF

    python3 /tmp/make_image.py
    rm /tmp/make_image.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
