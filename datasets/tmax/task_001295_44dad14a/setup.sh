#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc
    pip3 install pytest Pillow

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import os
from PIL import Image, ImageDraw

# Generate image
img = Image.new('RGB', (1000, 300), color = (255, 255, 255))
d = ImageDraw.Draw(img)
inject_str = chr(123) + chr(123) + "INJECT" + chr(125) + chr(125)
text = "LOCALIZATION FILTER RULES:\n1. If NumericValue is 'MISSING', gap-fill it by calculating the exact arithmetic mean\n   of the immediately preceding and immediately following valid NumericValues.\n2. REJECT the file if any gap-filled interpolated value is strictly greater than 420.00.\n3. REJECT the file if any TranslationString contains the exact substring '" + inject_str + "'."
d.text((10,10), text, fill=(0,0,0))
img.save('/app/loc_rules.png')

# Clean CSV
with open('/app/corpus/clean/clean1.csv', 'w') as f:
    f.write("1,100.0,Hello\n2,MISSING,World\n3,200.0,Test\n")

# Evil CSV 1 (value > 420)
with open('/app/corpus/evil/evil1.csv', 'w') as f:
    f.write("1,400.0,Hello\n2,MISSING,World\n3,450.0,Test\n")

# Evil CSV 2 (INJECT)
with open('/app/corpus/evil/evil2.csv', 'w') as f:
    f.write("1,100.0,Hello\n2,150.0,World " + inject_str + "\n3,200.0,Test\n")
EOF
    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
