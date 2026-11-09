#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc imagemagick fonts-liberation
    pip3 install pytest

    mkdir -p /app
    convert -background white -fill black -pointsize 24 label:"A B 5\nB C 2\nA D 8\nD B 1\nC E 3\nA E 9" /app/schema_graph.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
