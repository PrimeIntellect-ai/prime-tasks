#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required tools
    apt-get install -y imagemagick tesseract-ocr bc gawk fonts-dejavu-core

    # Create app directory
    mkdir -p /app

    # Generate the image with historical trend data
    convert -size 400x300 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
    -draw "text 20,40 'Year,Value' text 20,80 '1,3.1' text 20,120 '2,5.0' text 20,160 '3,6.8' text 20,200 '4,9.2' text 20,240 '5,11.1'" \
    /app/historical_trend.png

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
