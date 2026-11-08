#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app

    # Generate the legacy dashboard image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'API_SALT: 9fXb2_Qz1', fill=(0,0,0))
img.save('/app/legacy_dashboard.png')
"

    # Generate the config archive
    python3 -c "
import zlib
import struct

records = [
    '===CONFIG_CHANGE===\nTime: 1696161000\nUser: alice\nModule: network\n---\n+ dns=8.8.8.8\n===================\n',
    '===CONFIG_CHANGE===\nTime: 1696162500\nUser: bob\nModule: database\n---\n- max_conn=100\n+ max_conn=500\n===================\n',
    '===CONFIG_CHANGE===\nTime: 1696165000\nUser: charlie\nModule: network\n---\n+ ip_forwarding=1\n===================\n',
]

raw_data = ''.join(records).encode('utf-8')

with open('/app/config_archive.lzc', 'wb') as f:
    f.write(b'LZC1')
    chunk1 = zlib.compress(raw_data[:100])
    chunk2 = zlib.compress(raw_data[100:])

    f.write(struct.pack('>I', len(chunk1)))
    f.write(chunk1)
    f.write(struct.pack('>I', len(chunk2)))
    f.write(chunk2)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
