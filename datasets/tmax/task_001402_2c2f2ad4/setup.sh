#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    tesseract-ocr \
    imagemagick \
    build-essential \
    curl \
    fonts-dejavu-core

pip3 install pytest

mkdir -p /app
convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'PORT: 8090\nENDPOINT: /ping\nAUTH_KEY: vnc_alert_trigger_77'" /app/network_diagram.png
chmod 644 /app/network_diagram.png

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
