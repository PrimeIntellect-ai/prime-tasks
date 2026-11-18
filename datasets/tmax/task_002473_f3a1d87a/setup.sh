#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest

    # Install required packages for the task
    apt-get install -y tesseract-ocr libz-dev g++ imagemagick fonts-dejavu-core gzip coreutils

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create image fixture
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'URGENT: BANNED_SIGNATURE: EVIL_CORP_BACKDOOR_2024'" /app/security_bulletin.png

    # Create clean corpus
    for i in $(seq 1 10); do
        head -c 1000 /dev/urandom | gzip > /app/corpus/clean/clean_$i.gz
    done

    # Create evil corpus
    for i in $(seq 1 10); do
        (head -c 500 /dev/urandom; echo -n "EVIL_CORP_BACKDOOR_2024"; head -c 500 /dev/urandom) | gzip > /app/corpus/evil/evil_$i.gz
    done

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
