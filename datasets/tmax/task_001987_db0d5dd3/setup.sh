#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        gcc \
        git \
        imagemagick \
        fonts-dejavu-core \
        netcat-openbsd

    pip3 install pytest

    mkdir -p /app
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black \
    -draw "text 10,30 'SYSTEM RESTORE DATASHEET'" \
    -draw "text 10,60 'DATE: 2023-10-25'" \
    -draw "text 10,90 'STATUS: VERIFIED'" \
    -draw "text 10,120 'AUTH_TOKEN: 8f9b2a7c-4e1d-48a5-9032-abcdef123456'" \
    /app/backup_config.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
