#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y tesseract-ocr imagemagick gcc fonts-dejavu coreutils

    # Create /app directory
    mkdir -p /app

    # Generate release_tag.png
    convert -size 400x150 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'VERSION: 4.12.3'" -draw "text 20,100 'TOKEN: z9k-Delta-44'" /app/release_tag.png

    # Generate payload.bin
    dd if=/dev/urandom of=/app/payload.bin bs=1024 count=5

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
