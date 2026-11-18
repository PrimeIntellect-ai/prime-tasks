#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y imagemagick fonts-dejavu-core tesseract-ocr libtesseract-dev g++ make curl

    mkdir -p /app
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 '12 15 22 29 35'" /app/data_plot.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
