#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang-go
    pip3 install pytest Pillow

    mkdir -p /app

    python3 -c "
from PIL import Image, ImageDraw
text = '''CPU,RAM,Disk,Network,Failure
40.0,4.0,10.0,50.0,0
90.0,16.0,80.0,800.0,1
60.0,8.0,40.0,200.0,0
85.0,12.0,60.0,400.0,1
50.0,8.0,20.0,100.0,0'''
img = Image.new('RGB', (400, 200), color='white')
d = ImageDraw.Draw(img)
d.text((10,10), text, fill='black')
img.save('/app/data_table.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
