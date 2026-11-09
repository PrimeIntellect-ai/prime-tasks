#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        make \
        wget \
        curl \
        imagemagick \
        tesseract-ocr \
        libtesseract-dev \
        fonts-dejavu-core

    pip3 install --default-timeout=100 pytest flask fastapi uvicorn requests

    mkdir -p /app
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'mu=5.0 sigma=2.0'" /app/params.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
