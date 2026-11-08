#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick cargo fonts-liberation
    pip3 install pytest

    # Create directories
    mkdir -p /app/storage
    mkdir -p /app/backup

    # Create some dummy files to be backed up
    head -c 1M </dev/urandom > /app/storage/file1.dat
    head -c 2M </dev/urandom > /app/storage/file2.dat

    # Generate the legacy diagram image
    convert -size 600x200 canvas:white -fill black -pointsize 24 -gravity center -draw "text 0,0 'MIGRATION SPECS\nPORT: 8192\nQUOTA: 150 MB'" /app/legacy_diagram.png

    # Create user
    useradd -m -s /bin/bash user || true

    # Ensure permissions are correct for the user
    chown -R user:user /app/
    chmod -R 777 /app
    chmod -R 777 /home/user
