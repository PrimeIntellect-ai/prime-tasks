#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tesseract-ocr imagemagick
    pip3 install --default-timeout=100 pytest

    mkdir -p /app
    convert -size 600x100 xc:white -fill black -pointsize 24 -draw "text 10,50 'POLICY_SEED: OMEGA_PROTOCOL_7734'" /app/policy_secret.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
