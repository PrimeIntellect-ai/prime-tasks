#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-liberation
    pip3 install pytest Pillow pytesseract

    mkdir -p /app

    cat << 'EOF' > /app/archival_config.json
{
    "footer_prefix": "MANIFEST_START|",
    "footer_suffix": "|MANIFEST_END",
    "hash_algorithm": "sha256"
}
EOF

    cat << 'EOF' > /app/oracle_archive_tool.py
import sys
import json
import hashlib

def main():
    if len(sys.argv) != 3:
        sys.exit(1)

    in_file = sys.argv[1]
    out_file = sys.argv[2]

    with open('/app/archival_config.json', 'r') as f:
        config = json.load(f)

    with open(in_file, 'rb') as f:
        data = f.read()

    # Calculate hash of original data
    h = hashlib.new(config['hash_algorithm'])
    h.update(data)
    digest = h.hexdigest()

    # Transform: XOR with 0x5C
    transformed = bytearray([b ^ 0x5C for b in data])

    # Append manifest
    footer = f"{config['footer_prefix']}{digest}{config['footer_suffix']}".encode('utf-8')
    transformed.extend(footer)

    with open(out_file, 'wb') as f:
        f.write(transformed)

if __name__ == '__main__':
    main()
EOF

    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (1600, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf', 24)
except:
    font = ImageFont.load_default()
text = 'Algorithm: XOR every single byte of the input data with the hexadecimal value 0x5C. Do not change the order of the bytes.'
d.text((10, 10), text, fill=(0, 0, 0), font=font)
img.save('/app/archival_spec_page.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
