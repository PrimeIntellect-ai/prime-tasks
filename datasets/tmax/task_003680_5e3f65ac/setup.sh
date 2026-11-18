#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the fallback_config.png image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -annotate +20+40 "es-AR -> es-ES\nfr-CA -> fr-FR\npt-BR -> pt-PT\nzh-HK -> zh-TW" /app/fallback_config.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
