#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr
    pip3 install pytest

    mkdir -p /app
    convert -background white -fill black -pointsize 24 label:"HTTP_PORT=8123\nTCP_PORT=9321\nTOKEN=secure-infra-xyz" /app/config.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
