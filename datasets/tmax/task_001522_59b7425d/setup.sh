#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr fonts-dejavu-core
    pip3 install pytest pytesseract Pillow flask fastapi uvicorn python-multipart requests

    mkdir -p /app
    # Generate the backup policy image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'POLICY_ID: VAULTX_'" /app/backup_policy.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
