#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        gcc \
        build-essential \
        tar \
        coreutils

    pip3 install pytest

    mkdir -p /app/project_files/archives/
    mkdir -p /app/project_files/logs/
    mkdir -p /app/project_files/extracted/
    mkdir -p /app/project_files/corrupted/

    # Generate image
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black -draw "text 10,30 'CRITICAL CONFIGURATION:' text 10,60 'ENCODING=WINDOWS-1252' text 10,90 'THRESHOLD=4500'" /app/project_files/settings_scan.png

    # Generate archives
    for i in 1 2 3 4 5; do
        dd if=/dev/urandom of=/tmp/data$i.txt bs=1K count=10 status=none
        tar -czf /app/project_files/archives/archive$i.tar.gz -C /tmp data$i.txt
    done

    # Corrupt 2 of them
    truncate -s -100 /app/project_files/archives/archive4.tar.gz
    truncate -s -100 /app/project_files/archives/archive5.tar.gz

    # Generate log
    cat << 'EOF' > /tmp/gen_log.py
import uuid
import random

with open('/app/project_files/logs/system.log.utf8', 'w') as f:
    for _ in range(500):
        f.write(f"ID: {uuid.uuid4()}\n")
        f.write(f"Action: {random.choice(['READ', 'WRITE', 'DELETE'])}\n")
        f.write(f"Duration: {random.randint(1000, 8000)}ms\n")
        f.write(f"Message: Dummy log message payload\n")
        f.write("---\n")
EOF
    python3 /tmp/gen_log.py
    iconv -f UTF-8 -t WINDOWS-1252 /app/project_files/logs/system.log.utf8 > /app/project_files/logs/system.log
    rm /app/project_files/logs/system.log.utf8

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
