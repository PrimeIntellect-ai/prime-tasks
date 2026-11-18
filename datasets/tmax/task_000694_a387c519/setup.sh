#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        build-essential \
        curl

    pip3 install pytest

    mkdir -p /app

    # Generate the reference image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,60 'CHECKOUT_PROCEED_BUTTON'" /app/reference_ui.png

    # Create the CSV file
    cat << 'EOF' > /app/loc_events.csv
timestamp,ui_string,locale,views
1696118400,CHECKOUT_PROCEED_BUTTON,en-US,10
1696118400,CHECKOUT_PROCEED_BUTTON,fr-FR,5
1696161600,CHECKOUT_PROCEED_BUTTON,es-ES,7
1696204800,CHECKOUT_PROCEED_BUTTON,en-US,20
1696204800,OTHER_BUTTON,en-US,100
1696291200,CHECKOUT_PROCEED_BUTTON,de-DE,15
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
