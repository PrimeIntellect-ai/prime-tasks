#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr git
    pip3 install pytest Pillow

    mkdir -p /app/clean /app/evil

    # Generate the image using Python
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), 'RESTRICTED_BGP_PEER=\"198.51.100.\"', fill=(0, 0, 0))
img.save('/app/network_policy.png')
"

    # Generate clean corpus
    for i in $(seq 1 20); do
        echo "route add default gw 10.0.0.$i" > /app/clean/config_$i.txt
        echo "BGP_PEER=\"203.0.113.$i\"" >> /app/clean/config_$i.txt
    done

    # Generate evil corpus
    for i in $(seq 1 20); do
        echo "route add default gw 10.0.0.$i" > /app/evil/config_$i.txt
        echo "BGP_PEER=\"198.51.100.$i\"" >> /app/evil/config_$i.txt
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
