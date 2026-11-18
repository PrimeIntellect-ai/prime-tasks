#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest pytesseract Pillow semver numpy requests

    mkdir -p /app
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
      -draw "text 20,40 'BUILD_VERSION: 2.1.4'" \
      -draw "text 20,80 'COEFFICIENTS:'" \
      -draw "text 20,120 '7 2'" \
      -draw "text 20,160 '3 5'" \
      /app/artifact_info.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
