#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-liberation
    pip3 install pytest Pillow

    mkdir -p /app/corpus/clean /app/corpus/evil

    python3 -c '
import os
import random
from PIL import Image, ImageDraw, ImageFont

# Generate image
img = Image.new("RGB", (600, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 36)
except:
    font = ImageFont.load_default()
d.text((20, 50), "ARCHITECTURE LIMITS\nMAX_DEPTH=12\nTIMEOUT=30s", fill=(0, 0, 0), font=font)
img.save("/app/system_diagram.png")

# Generate clean files (depth <= 12)
for i in range(20):
    depth = random.randint(1, 12)
    content = "{" * depth + "}" * depth
    with open(f"/app/corpus/clean/file_{i}.txt", "w") as f:
        f.write(content)

# Generate evil files (unbalanced or depth > 12)
for i in range(10):
    depth = random.randint(13, 25)
    content = "{" * depth + "}" * depth
    with open(f"/app/corpus/evil/file_depth_{i}.txt", "w") as f:
        f.write(content)

for i in range(10):
    content = "{{" + "}"
    with open(f"/app/corpus/evil/file_unbal_{i}.txt", "w") as f:
        f.write(content)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
