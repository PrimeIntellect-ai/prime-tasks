#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr socat cron imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    convert -size 600x300 xc:white -font DejaVu-Sans -pointsize 24 -fill black -annotate +20+50 "Microservice Routing Configuration:\nGatewayPort: 8111\nAppPort: 8222\nDataPort: 8333" /app/network_topology.png
    chmod 644 /app/network_topology.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
