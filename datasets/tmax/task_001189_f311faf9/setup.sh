#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
pip3 install pytest

mkdir -p /app
convert -size 200x50 xc:white -font DejaVu-Sans -pointsize 20 -fill black -annotate +10+30 'SEC-TKN-88A21F9C' /app/policy_token.png
chmod -R 777 /app

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
