#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu
    pip3 install pytest flask fastapi uvicorn h5py numpy scipy pytesseract requests pillow

    mkdir -p /app
    # Generate the config image
    convert -size 200x50 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,30 'ALPHA=0.05'" /app/config.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
