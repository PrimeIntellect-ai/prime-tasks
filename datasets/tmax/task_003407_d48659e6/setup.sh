#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr zip xz-utils
    pip3 install pytest pytesseract Pillow

    mkdir -p /app
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color='white')
d = ImageDraw.Draw(img)
d.text((10,10), 'BANNED_EXTENSION=.dll', fill='black')
img.save('/app/curation_rules.png')
"

    mkdir -p /home/user/incoming_artifacts
    cd /home/user/incoming_artifacts

    # Create archive1.zip
    touch safe_bin1.exe library.dll
    zip archive1.zip safe_bin1.exe library.dll
    rm safe_bin1.exe library.dll

    # Create archive2.zip with zip slip
    touch safe_bin2.exe
    python3 -c "
import zipfile
with zipfile.ZipFile('archive2.zip', 'w') as z:
    z.write('safe_bin2.exe')
    z.writestr('../../../../home/user/pwned.txt', 'pwned')
"
    rm safe_bin2.exe

    # Create archive3.zip
    touch safe_bin3.exe
    zip archive3.zip safe_bin3.exe
    rm safe_bin3.exe

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
