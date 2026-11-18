#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr g++ wget fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    # Generate a simple image containing the required config text
    convert -size 400x100 xc:black -font DejaVu-Sans-Mono -pointsize 18 -fill white \
    -draw "text 10,40 'EPSILON=1e-9'" \
    -draw "text 10,70 'MAX_ITERATIONS=1000'" \
    /app/error_snapshot.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
