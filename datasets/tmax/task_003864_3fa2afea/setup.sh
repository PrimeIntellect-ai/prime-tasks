#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu

    pip3 install pytest

    # Create directories
    mkdir -p /app/docs
    mkdir -p /app/test_corpora/evil
    mkdir -p /app/test_corpora/clean
    mkdir -p /home/user/samples

    # Generate auth stamp image
    # Note: imagemagick security policy might block some operations, but drawing text on xc:white should be fine.
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'AUTH_TOKEN=OmegaDoc99'" /app/docs/auth_stamp.png

    # Create user
    useradd -m -s /bin/bash user || true

    # Fix permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
