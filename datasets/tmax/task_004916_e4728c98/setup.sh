#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

    # Install system packages
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        golang-go \
        fonts-dejavu

    # Install Python packages
    pip3 install pytest requests

    # Create directories and observational data image
    mkdir -p /app
    convert -size 400x300 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 20,50 'Time Concentration' text 20,90 '0.0  100.00' text 20,130 '1.0  60.65' text 20,170 '2.0  36.79' text 20,210 '3.0  22.31'" \
        /app/observational_data.png

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
