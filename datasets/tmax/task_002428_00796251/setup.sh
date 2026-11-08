#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        imagemagick \
        tesseract-ocr \
        xz-utils \
        fonts-dejavu \
        coreutils \
        bash

    pip3 install pytest

    mkdir -p /app/corrupted_docs/dir1/dir2

    # Generate stamp.png
    convert -size 400x50 xc:white -font DejaVu-Sans -pointsize 20 -fill black -draw "text 10,30 'SECURITY-CLASSIFICATION: TOP-SECRET-AURA'" /app/stamp.png

    # Create corrupted docs structure
    echo -e "System Overview\nThis is a DEPRECATED feature.\nCore logic goes here." > /app/corrupted_docs/file_A.txt
    echo -e "API Endpoints\nDEPRECATED: v1 endpoint\nNew v2 endpoint is active." > /app/corrupted_docs/dir1/file_B.txt

    ln -s /app/corrupted_docs/file_A.txt /app/corrupted_docs/dir1/link_A.txt
    ln -s /app/corrupted_docs/dir1 /app/corrupted_docs/dir1/dir2/loop

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
