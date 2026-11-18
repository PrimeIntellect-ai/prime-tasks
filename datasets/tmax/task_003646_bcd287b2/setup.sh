#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black -draw "text 10,30 'STORE: SUPERMART' text 10,60 'DATE: 2023-10-25' text 10,90 'CARD: 4128-9999-1234-5678' text 10,120 'TOTAL: $45.99'" /app/secret_receipt.png
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
