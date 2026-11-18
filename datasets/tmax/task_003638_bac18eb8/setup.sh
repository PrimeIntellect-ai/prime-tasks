#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task and setup
    apt-get install -y imagemagick tesseract-ocr libmicrohttpd-dev nginx curl gcc make fonts-dejavu-core

    # Create the /app directory
    mkdir -p /app

    # Generate the architecture diagram image with the hidden token
    convert -size 800x400 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 50,100 'Legacy Architecture Diagram'" \
        -draw "text 50,200 'Internal Services -> Gateway'" \
        -draw "text 50,300 'CI_TOKEN: 8A4F-99B2-C7E1-XYZ9'" \
        /app/arch_diagram.png

    # Create the user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
