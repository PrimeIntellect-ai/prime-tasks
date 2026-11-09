#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        gcc

    pip3 install pytest

    # Create the diagram image
    mkdir -p /app
    convert -background white -fill black -font DejaVu-Sans -pointsize 24 label:"TRAFFIC SPLIT POLICY:\nservice-v1 : 75%\nservice-v2 : 25%" /app/diagram.png

    # Create the manifests
    mkdir -p /home/user/manifests
    echo '{"app": "service-v1"}' > /home/user/manifests/v1.json
    echo '{"app": "service-v2"}' > /home/user/manifests/v2.json

    # Create user and adjust permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
