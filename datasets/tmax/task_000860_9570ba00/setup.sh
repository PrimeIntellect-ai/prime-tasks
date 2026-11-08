#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y imagemagick tesseract-ocr gcc netcat-openbsd fonts-dejavu-core

    mkdir -p /app

    # Create the FASTA file
    cat << 'EOF' > /app/protein.fasta
>protein_1
ACDEFGHIKLMNPQRSTVWY
CCCCC
EOF

    # Create the image fixture
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'Alpha: 2.5'" -draw "text 20,100 'Beta: 8.0'" /app/lab_notes.png

    # Create the user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
