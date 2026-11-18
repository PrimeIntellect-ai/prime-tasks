#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        imagemagick \
        fonts-dejavu-core \
        tesseract-ocr \
        cargo \
        curl

    pip3 install pytest

    mkdir -p /app
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 20 -fill black \
        -draw "text 20,50 'Imputation Rule: Linear Regression (B on A).'" \
        -draw "text 20,90 'CI: 95% Normal (Z=1.96).'" \
        -draw "text 20,130 'Imputed values must be rounded to 4 decimal places.'" \
        /app/schema_rules.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
