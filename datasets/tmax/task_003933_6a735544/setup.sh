#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick openssh-server openssh-client netcat-openbsd fonts-liberation
pip3 install pytest

mkdir -p /app
convert -background white -fill black -font Courier -pointsize 24 label:"RELIANT_DEFENSE_99" /app/secret_note.png

mkdir -p /run/sshd
chmod 755 /run/sshd

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
