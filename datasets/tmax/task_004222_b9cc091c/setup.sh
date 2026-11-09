#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip fonts-liberation
    pip3 install pytest Pillow

    mkdir -p /app

    # Create oracle obfuscator
    cat << 'EOF' > /app/oracle_obfuscator
#!/usr/bin/env python3
import sys
def process():
    data = sys.stdin.buffer.read()
    out = bytearray()
    for b in data:
        x = b ^ 0x5A
        if x == 0x13:
            out.append(0x31)
        elif x == 0x31:
            out.append(0x13)
        else:
            out.append(x)
    sys.stdout.buffer.write(out)
if __name__ == '__main__':
    process()
EOF
    chmod +x /app/oracle_obfuscator

    # Generate image
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw, ImageFont
import textwrap

text = "CONFIDENTIAL: Artifact Obfuscation v2. Read bytes from standard input. Rule 1: XOR each byte with the hex value 5A. Rule 2: If the XOR result is exactly the hex value 13, output the hex value 31 instead. If the XOR result is exactly the hex value 31, output the hex value 13 instead. Write all results to standard output."

img = Image.new('RGB', (1000, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 24)
except:
    font = ImageFont.load_default()

lines = textwrap.wrap(text, width=70)
y_text = 20
for line in lines:
    d.text((20, y_text), line, font=font, fill=(0, 0, 0))
    y_text += 35

img.save('/app/obfuscation_rules.png')
EOF
    python3 /tmp/gen_image.py
    rm /tmp/gen_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
