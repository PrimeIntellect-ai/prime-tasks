#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

    # Install system dependencies with --no-install-recommends to save time and space
    apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        tesseract-ocr \
        libtesseract-dev \
        imagemagick \
        openmpi-bin \
        libopenmpi-dev \
        fonts-liberation \
        ghostscript

    # Install Python packages using pip
    pip3 install --no-cache-dir pytest mpi4py networkx h5py matplotlib pytesseract Pillow flask requests

    # Create application directory
    mkdir -p /app

    # Disable ImageMagick security policies that might block text rendering
    sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/g' /etc/ImageMagick-6/policy.xml || true
    sed -i 's/rights="none" pattern="@\*"/rights="read|write" pattern="@\*"/g' /etc/ImageMagick-6/policy.xml || true

    # Generate the experiment parameters image
    convert -size 400x200 xc:white -fill black -pointsize 20 -draw "text 10,30 'DIFFUSION EXPERIMENT SETUP\n==========================\nK_BASE: 0.015\nTHRESHOLD: 0.0002'" /app/experiment_params.png

    # Set permissions for /app
    chmod -R 777 /app

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
