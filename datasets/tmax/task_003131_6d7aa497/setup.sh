#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tesseract-ocr imagemagick
    pip3 install pytest

    mkdir -p /app
    # Remove ImageMagick policy to avoid restrictions on drawing/creating images
    rm -f /etc/ImageMagick-6/policy.xml || true
    convert -size 300x100 xc:white -fill black -pointsize 24 -gravity center -draw "text 0,0 'FILTER_TYPE=REFUND'" /app/rule.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
