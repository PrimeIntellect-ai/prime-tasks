#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        zlib1g-dev \
        gcc \
        make \
        imagemagick \
        fonts-dejavu-core \
        gzip

    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/dataset/alpha/beta
    mkdir -p /home/user/dataset/gamma

    # Create symlinks
    ln -s ../../alpha /home/user/dataset/alpha/beta/loop_to_alpha
    ln -s ../gamma /home/user/dataset/gamma/loop_to_gamma

    # Create image
    mkdir -p /app
    # Fix ImageMagick security policy for PDF/fonts if needed, but xc:white and text should work
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 36 -fill black -draw "text 20,60 'LAB-TKN-8891A'" /app/dataset_auth.png

    # Create data files
    cat <<EOF > /home/user/dataset/alpha/data1.json
{"id": 101, "is_research_target": true, "name": "sample_A"}
{"id": 102, "is_research_target": false, "name": "sample_B"}
EOF
    gzip /home/user/dataset/alpha/data1.json

    cat <<EOF > /home/user/dataset/gamma/data2.json
{"id": 103, "is_research_target": true, "name": "sample_C"}
EOF
    gzip /home/user/dataset/gamma/data2.json

    chmod -R 777 /home/user
    chmod -R 777 /app
