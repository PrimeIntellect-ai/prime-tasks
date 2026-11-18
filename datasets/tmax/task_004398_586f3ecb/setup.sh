#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install necessary packages for setup and agent task
    apt-get install -y imagemagick gcc g++ libssl-dev tesseract-ocr wget curl binutils fonts-dejavu-core

    # Create app directory
    mkdir -p /app

    # Generate the master key image
    convert -size 600x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -annotate +10+50 "M4ST3R_K3Y_2024_R0T4T10N" /app/new_master_key.png

    # Generate the legacy crypto ELF file
    cat << 'EOF' > /tmp/dummy.c
__attribute__((section(".secret_salt"))) const char salt[] = "L3g4cy_S@1t_88";
EOF
    gcc -shared -o /app/legacy_crypto.so /tmp/dummy.c
    rm /tmp/dummy.c

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
