#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-liberation
    pip3 install pytest pytesseract Pillow flask fastapi uvicorn pandas requests numpy

    mkdir -p /app

    cat << 'EOF' > /app/dirty_corpus.csv
id,text_entry,value_a,value_b
1,"Café ñandú ¡hola! 😊",10.0,2.0
2,"  𝕿𝖍𝖊 𝖖𝖚𝖎𝖈𝖐 𝖇𝖗𝖔𝖜𝖓 𝖋𝖔𝖝  ",,5.0
3,"こんにちは世界 123",30.0,10.0
4,"Ænima song—test!",,1.5
5,"Русский текст...",50.0,0.0
EOF

    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (600, 200), color='white')
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf', 40)
except:
    font = ImageFont.load_default()
d.text((20, 50), 'GLOBAL MULTIPLIER: 3.14', fill='black', font=font)
img.save('/app/reference_key.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
