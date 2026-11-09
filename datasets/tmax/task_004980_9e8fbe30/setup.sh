#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr git socat netcat-openbsd imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black -annotate +10+30 "Service Configuration:\nWeb Port: 8181\nToken: AlphaX9\nMock SSH: 3131" /app/architecture.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
