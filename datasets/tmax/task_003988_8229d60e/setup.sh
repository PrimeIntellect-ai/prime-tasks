#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        binutils \
        file \
        imagemagick \
        fonts-liberation \
        gawk \
        sed \
        grep \
        coreutils

    pip3 install pytest

    # Create app directory and generate the memo image
    mkdir -p /app
    convert -size 800x200 canvas:white -fill black -pointsize 24 -draw "text 50,100 'APPROVED REDIRECT DOMAIN: auth-secure.internal.corp'" /app/memo.png

    # Create user and set up server binary
    useradd -m -s /bin/bash user || true
    cp /bin/ls /home/user/server.bin

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user
