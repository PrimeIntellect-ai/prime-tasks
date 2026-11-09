#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nasm tesseract-ocr imagemagick fonts-dejavu-core sudo
pip3 install pytest Flask requests

mkdir -p /app
convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'AUTH_SEED: K3yV4lUe99'" /app/build_ticket.png

useradd -m -s /bin/bash user || true
echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
chmod -R 777 /home/user
chmod -R 777 /app
