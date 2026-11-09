#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick gcc libc6-dev
pip3 install pytest

mkdir -p /app
convert -size 400x200 canvas:white -fill black -pointsize 24 -annotate +20+50 "Domain Specs:" -annotate +20+90 "W = 2.0" -annotate +20+130 "H = 1.0" -annotate +20+170 "Top BC: u(x,H) = sin(pi*x/2)" /app/domain_specs.png

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
