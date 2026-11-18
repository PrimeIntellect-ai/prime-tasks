#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    # Create directories
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Generate the image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color='white')
d = ImageDraw.Draw(img)
text = '''CAPACITY PLANNING RULES
-----------------------
Max CPU: 75.0%
Max MEM: 40.0%
Ignore Path: ^/usr/libexec/.*'''
d.text((10,10), text, fill='black')
img.save('/app/capacity_rules.png')
"

    # Populate corpora
    echo "101,appuser,80.5,12.0,/opt/custom/app" > /app/corpora/evil/evil1.txt
    echo "102,appuser,10.0,45.0,/bin/bash" > /app/corpora/evil/evil2.txt
    echo "103,appuser,80.0,50.0,/bin/bash" > /app/corpora/evil/evil3.txt

    echo "201,appuser,12.0,12.0,/opt/custom/app" > /app/corpora/clean/clean1.txt
    echo "202,root,99.0,80.0,/usr/libexec/system-daemon" > /app/corpora/clean/clean2.txt
    echo "203,root,10.0,10.0,/usr/libexec/other" > /app/corpora/clean/clean3.txt
    echo "204,appuser,75.0,40.0,/opt/custom/app" > /app/corpora/clean/clean4.txt

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
