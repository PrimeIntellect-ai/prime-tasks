#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    convert -size 600x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'Token: SECRET-ETL-774 PrimaryKey: tx_id'" /app/auth_schema.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
