#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-liberation
    pip3 install pytest

    mkdir -p /app
    convert -background white -fill black -pointsize 24 label:"Region: us-east-1, Cost: \$0.02/GB\nRegion: eu-central-1, Cost: \$0.04/GB\nRegion: ap-northeast-1, Cost: \$0.09/GB\nRegion: sa-east-1, Cost: \$0.15/GB" /app/transit_costs.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
