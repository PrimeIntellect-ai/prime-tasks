#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        binutils \
        golang-go \
        imagemagick

    pip3 install pytest

    # Create /app directory
    mkdir -p /app

    # Generate auth ticket image
    convert -size 400x100 xc:white -pointsize 40 -fill black -annotate +20+60 'TKN_A93F8B2C' /app/auth_ticket.png

    # Set permissions
    chmod -R 777 /app

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
