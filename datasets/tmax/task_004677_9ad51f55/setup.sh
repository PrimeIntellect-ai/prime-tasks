#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Install required system packages
apt-get install -y tesseract-ocr imagemagick fonts-dejavu-core

# Install helpful Python packages for the agent
pip3 install flask fastapi uvicorn pytesseract requests

# Create directories
mkdir -p /app/safe_storage

# Remove ImageMagick policy file to ensure convert command works without restrictions
rm -f /etc/ImageMagick-6/policy.xml

# Generate the server configuration image
convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
    -draw "text 20,50 'ListenPort: 8555'" \
    -draw "text 20,100 'AdminToken: ALPHA-99-BETA'" \
    /app/server_config.png

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
