#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr cargo rustc curl
    pip3 install pytest Pillow

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /tmp/setup_data.py
import os
import json
import random
import string
from PIL import Image, ImageDraw

img = Image.new('RGB', (200, 100), color='white')
d = ImageDraw.Draw(img)
d.text((10,10), "W=12\nD=18.5\nS=Cyrillic", fill='black')
img.save("/app/config.png")

def random_string(length, charset):
    return ''.join(random.choice(charset) for _ in range(length))

ascii_chars = string.ascii_letters + string.digits + " "
cyrillic_chars = "".join(chr(i) for i in range(0x0400, 0x04FF))

for i in range(20):
    with open(f"/app/corpus/clean/file_{i}.jsonl", "w") as f:
        for j in range(20):
            text = random_string(50, ascii_chars) + random_string(5, cyrillic_chars)
            f.write(json.dumps({"timestamp": j, "text": text}) + "\n")

for i in range(20):
    with open(f"/app/corpus/evil/file_{i}.jsonl", "w") as f:
        base_text = random_string(20, ascii_chars) + random_string(5, cyrillic_chars)
        for j in range(20):
            text = base_text if j >= 5 else random_string(50, ascii_chars)
            f.write(json.dumps({"timestamp": j, "text": text}) + "\n")
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
