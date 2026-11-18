#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        gcc \
        libgomp1 \
        imagemagick \
        fonts-dejavu

    pip3 install pytest flask requests pillow

    # Create the config image
    mkdir -p /app
    convert -size 200x50 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,30 'COEFF=0.0025'" /app/config.png

    # Setup user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
