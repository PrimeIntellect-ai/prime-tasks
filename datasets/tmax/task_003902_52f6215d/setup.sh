#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu
    pip3 install pytest

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean
    mkdir -p /home/user/logs

    # Generate billing_rules.png
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'EXEMPT_PROJECT: KRAKEN'" /app/billing_rules.png

    # Generate evil corpus
    echo -e "[INFO] starting\n[DEBUG] variable loaded\n[INFO] done" > /app/corpus/evil/evil1.log
    echo -e "[DEBUG] connection timeout" > /app/corpus/evil/evil2.log
    echo -e "Nothing much but a [DEBUG] statement" > /app/corpus/evil/test_debug.log

    # Generate clean corpus
    echo -e "[INFO] normal operations" > /app/corpus/clean/clean1.log
    echo -e "[DEBUG] testing" > /app/corpus/clean/clean2.txt
    echo -e "[DEBUG] failure\n[ERROR] crash" > /app/corpus/clean/clean3.log
    echo -e "[DEBUG] testing integration for EXEMPT_PROJECT: KRAKEN" > /app/corpus/clean/clean4.log
    echo -e "random binary data or text" > /app/corpus/clean/clean5.data

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
