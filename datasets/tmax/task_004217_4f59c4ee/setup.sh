#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick cargo rustc
    pip3 install pytest

    mkdir -p /app
    convert -background white -fill black -pointsize 24 label:'SECURE_AUDIT_9982' /app/target_info.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
