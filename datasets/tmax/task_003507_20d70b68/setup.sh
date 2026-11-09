#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu
    pip3 install pytest

    mkdir -p /home/user/docs /app
    echo "Sample documentation text." > /home/user/docs/intro.md
    echo "More technical details." > /home/user/docs/details.md
    ln -s /home/user/docs /home/user/docs/shortcut

    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 36 -fill black -draw "text 20,60 'DocBackup99'" /app/password.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
