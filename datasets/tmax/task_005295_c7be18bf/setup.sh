#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc
pip3 install pytest pillow

mkdir -p /app

cat << 'EOF' > /app/legacy_hash.c
#include <stdio.h>
int generate_token(int id) {
    return id * 999333 + 42;
}
EOF

python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = '''DB SCHEMA: table 'users', columns: id INTEGER, name TEXT, role TEXT
ENCODING: windows-1252
HTTP PORT: 8080
TCP PORT: 8081'''
d.text((10,10), text, fill=(0,0,0))
img.save('/app/system_diagram.png')
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
