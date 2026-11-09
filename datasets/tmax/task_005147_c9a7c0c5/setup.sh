#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        iproute2 \
        openssl

    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate the image
    convert -size 1000x200 xc:white -fill black -font DejaVu-Sans -pointsize 20 \
        -annotate +20+50 "SECURITY ALERT. Block all requests matching: User-Agent: EvilBot/v3.4.1 OR Path: /system/backup.tar.gz" \
        /app/waf_rules.png

    # Generate Clean Corpus
    for i in $(seq 1 50); do
        cat <<EOF > /app/corpus/clean/req${i}.txt
GET /index.html HTTP/1.1
Host: example.com
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)
Accept: */*

EOF
    done

    # Generate Evil Corpus (User-Agent)
    for i in $(seq 1 25); do
        cat <<EOF > /app/corpus/evil/req_ua${i}.txt
GET /index.html HTTP/1.1
Host: example.com
User-Agent: EvilBot/v3.4.1
Accept: */*

EOF
    done

    # Generate Evil Corpus (Path)
    for i in $(seq 1 25); do
        cat <<EOF > /app/corpus/evil/req_path${i}.txt
GET /system/backup.tar.gz HTTP/1.1
Host: example.com
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)
Accept: */*

EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
