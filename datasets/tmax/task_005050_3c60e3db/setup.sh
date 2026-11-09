#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr curl fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    convert -size 500x100 xc:white -fill black -pointsize 24 -draw "text 10,50 'ATTACKER_DOMAIN: evil-exfil-server.xyz'" /app/evidence.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
