#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick build-essential fonts-liberation
    pip3 install pytest

    mkdir -p /app
    convert -size 400x200 xc:white -fill black -pointsize 24 -draw "text 10,50 'Backup Node Config - PORT: 8844'" -draw "text 10,100 'VAULT_TOKEN: SEC-99-BKUP-X7'" /app/arch_diagram.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
