#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang-go
    pip3 install pytest pillow

    mkdir -p /app/repository

    # Generate the manifest image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color='white')
d = ImageDraw.Draw(img)
text = 'REPOSITORY MANIFEST\nVERSION: 2.4\nDECRYPTION_KEY: 137\nSTATUS: ARCHIVED'
d.text((20, 50), text, fill='black')
img.save('/app/manifest.png')
"

    # Generate the encrypted and RLE-encoded blob
    python3 -c "
csv_text = '''id,name,size
1,sys-core.tar.gz,450
2,legacy-db.zip,2048
3,net-utils.tgz,890
4,media-pack.rar,5000
5,auth-lib.tar.gz,120
'''
out = bytearray()
i = 0
while i < len(csv_text):
    c = csv_text[i]
    count = 1
    while i + count < len(csv_text) and csv_text[i + count] == c and count < 255:
        count += 1
    out.append(count ^ 137)
    out.append(ord(c) ^ 137)
    i += count
with open('/app/repository/blob.bin', 'wb') as f:
    f.write(out)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
