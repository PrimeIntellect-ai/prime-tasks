#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core

    pip3 install pytest pytesseract numpy pandas notebook flask fastapi uvicorn requests pillow

    mkdir -p /app

    # Create the image with parameters
    # Modify ImageMagick policy to allow text to image if needed, but usually fine for simple annotate
    sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/g' /etc/ImageMagick-6/policy.xml || true
    convert -size 400x400 xc:white -font DejaVu-Sans -pointsize 24 -fill black -annotate +20+40 "S0=150\nmu=0.08\nsigma=0.15\nT=2.0\nSeed=42\nN_paths=10000" /app/params.png

    # Create historical.csv
    cat << 'EOF' > /app/historical.csv
Final_Price
165.20
172.10
168.50
178.40
169.30
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
