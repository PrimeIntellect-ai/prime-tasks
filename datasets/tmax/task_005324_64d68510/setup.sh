#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Generate version_tag.png
    convert -size 200x50 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,35 'v7.4.2-RCO'" /app/version_tag.png

    # Create translations.csv
    cat << 'EOF' > /app/translations.csv
Key,Lang,Source,Translation
WELCOME_MSG,en,Welcome to the app!,"Welcome to the app!"
WELCOME_MSG,es,Welcome to the app!,"¡Bienvenido a
la aplicación!"
ERR_01,es,File not found,"Archivo
no encontrado"
WELCOME_ALT,es,Welcome to the app!,"¡Hola!"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
