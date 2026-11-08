#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Generate the policy image
    convert -size 400x300 xc:white -font DejaVu-Sans -pointsize 20 -fill black -annotate +20+40 "ROUTING POLICY\n/admin -> 9000\n/api/v2 -> 8082\n/api/v1 -> 8081\n/static -> 8080\nDEFAULT -> 8000" /app/policy.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
