#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    tesseract-ocr \
    tesseract-ocr-eng \
    imagemagick \
    fonts-dejavu-core

pip3 install pytest

mkdir -p /app

# Generate the image with the required text
convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
    -draw "text 20,50 'LISTEN_PORT: 8222'" \
    -draw "text 20,100 'AUTH_TOKEN: tr0ub4dour'" \
    /app/alert_config.png

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
