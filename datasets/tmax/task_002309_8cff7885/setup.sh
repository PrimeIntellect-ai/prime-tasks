#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install necessary packages for the task and image generation
    apt-get install -y \
        imagemagick \
        fonts-dejavu-core \
        tzdata \
        locales \
        build-essential \
        tesseract-ocr \
        openssh-server \
        openssh-client \
        podman \
        sudo \
        curl \
        systemd \
        systemd-sysv

    # Generate the secret passcode image
    mkdir -p /app
    convert -size 400x150 xc:white -font DejaVu-Sans-Bold -pointsize 48 -fill black -draw "text 20,80 'A9b3FkL2'" /app/secret_passcode.png

    # Create the user and configure passwordless sudo
    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    # Ensure correct permissions
    chmod -R 777 /home/user
    chmod 777 /app
