#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go imagemagick fonts-dejavu-core tesseract-ocr
pip3 install pytest

# Create the mathematical formula image
mkdir -p /app
convert -size 1000x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -annotate +20+100 'TARGET PDF: P(x, y) \propto \exp(-1.5 x^2 - 2.5 y^2 + x y)' /app/formula.png

# Create user and working directory
useradd -m -s /bin/bash user || true
mkdir -p /home/user/mcmc

chmod -R 777 /home/user
chmod -R 777 /app
