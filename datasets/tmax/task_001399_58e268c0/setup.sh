#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick gcc build-essential fonts-dejavu
    pip3 install pytest

    mkdir -p /app

    # Create image fixture
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,40 'SYSTEM PARAMETERS:' text 10,80 'EMA_ALPHA=0.125' text 10,120 'MAX_PAYLOAD=32767'" /app/config_params.png

    # Create memory dump
    dd if=/dev/urandom of=/app/memory.dmp bs=1M count=5
    printf "CRASH_TX:9f86d081884c7d659a2feaa0c55ad015" | dd of=/app/memory.dmp bs=1 seek=2048576 conv=notrunc

    # Create corpora
    mkdir -p /home/user/corpora/clean /home/user/corpora/evil

    printf "TX:11111111111111111111111111111111\nSIZE:1024\n" > /home/user/corpora/clean/log1.txt
    printf "TX:22222222222222222222222222222222\nSIZE:32767\n" > /home/user/corpora/clean/log2.txt

    printf "TX:9f86d081884c7d659a2feaa0c55ad015\nSIZE:100\n" > /home/user/corpora/evil/log1.txt
    printf "TX:33333333333333333333333333333333\nSIZE:32768\n" > /home/user/corpora/evil/log2.txt
    printf "TX:44444444444444444444444444444444\nSIZE:-500\n" > /home/user/corpora/evil/log3.txt
    printf "TX:55555555555555555555555555555555\nSIZE:2147483648\n" > /home/user/corpora/evil/log4.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
