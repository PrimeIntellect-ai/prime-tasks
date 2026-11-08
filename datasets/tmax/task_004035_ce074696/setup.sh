#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate the scan_config.png image
    convert -size 600x200 xc:white \
        -font DejaVu-Sans -pointsize 20 -fill black \
        -draw "text 20,50 'Target: *'" \
        -draw "text 20,90 'User-Agent: X-RedTeam-Scanner/v2.4'" \
        -draw "text 20,130 'Payload: /api/v1/system_check'" \
        /app/scan_config.png

    # Create clean logs
    for i in $(seq 1 5); do
        cat <<EOF > /app/corpus/clean/log_$i.log
192.168.1.$i - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326 "-" "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
192.168.1.$i - - [10/Oct/2023:13:55:37 -0700] "GET /style.css HTTP/1.1" 200 1024 "http://example.com/index.html" "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
EOF
    done

    # Create evil logs
    for i in $(seq 1 5); do
        cat <<EOF > /app/corpus/evil/log_$i.log
192.168.1.10$i - - [10/Oct/2023:14:00:00 -0700] "GET /about.html HTTP/1.1" 200 1500 "-" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
10.0.0.$i - - [10/Oct/2023:14:05:12 -0700] "GET /api/v1/system_check HTTP/1.1" 404 512 "-" "X-RedTeam-Scanner/v2.4"
EOF
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
