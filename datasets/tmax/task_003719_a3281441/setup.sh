#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick tar fonts-liberation
pip3 install pytest

mkdir -p /app/backup/
echo "Device: UUID=55aa-88bb, Mountpoint: /restore/db, Type: xfs, Options: rw,noatime" > /tmp/disk_info.log
tar -czf /app/backup/archive_55.tar.gz -C /tmp disk_info.log

convert -background white -fill black -font Liberation-Mono -pointsize 24 label:"RESTORE DIRECTIVE\nArchive: /app/backup/archive_55.tar.gz\nRecoveryKey: AlphaOmega-992\nServerPort: 9050" /app/restore_directive.png

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
