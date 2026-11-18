#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/logs
    echo "data" > /app/logs/raw_STORAGE-77X_001.log
    echo "data" > /app/logs/raw_STORAGE-77X_002.log
    echo "data" > /app/logs/raw_STORAGE-77X_003.log
    echo "data" > /app/logs/raw_OTHER-11A_001.log

    # Generate the image with the text
    convert -pointsize 48 label:"STORAGE-77X" /app/system_tag.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
