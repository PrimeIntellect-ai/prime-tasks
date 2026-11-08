#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server tesseract-ocr gcc curl imagemagick fonts-dejavu-core procps
    pip3 install pytest

    # Create the target image using ImageMagick
    mkdir -p /app
    convert -size 600x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'CONFIDENTIAL-KEY-8842-OMEGA'" /app/target_image.png || \
    convert -pointsize 24 label:'CONFIDENTIAL-KEY-8842-OMEGA' /app/target_image.png

    # Create user and set up SSH
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -b 2048 -f /home/user/.ssh/id_rsa -N ""
    cat /home/user/.ssh/id_rsa.pub > /home/user/.ssh/authorized_keys

    # Configure sshd to ignore file permissions since we must chmod 777 the home directory
    mkdir -p /run/sshd
    echo "StrictModes no" >> /etc/ssh/sshd_config

    # Ensure the testing framework can start sshd and tests pass
    chmod -R 777 /home/user
