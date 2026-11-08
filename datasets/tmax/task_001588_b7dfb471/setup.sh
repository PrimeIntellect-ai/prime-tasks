#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install system dependencies for OCR and image generation
    apt-get install -y tesseract-ocr imagemagick fonts-dejavu-core

    # Install Python dependencies
    pip3 install numpy pytesseract Pillow

    # Create directories
    mkdir -p /app

    # Generate the image artefact
    convert -size 400x150 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 10,40 'A = 1.5'" \
        -draw "text 10,70 'C = -0.5'" \
        -draw "text 10,100 'G = 0.5'" \
        -draw "text 10,130 'T = -1.5'" \
        -draw "text 200,85 'Window = 1000'" /app/note.png

    # Generate the genome sequence
    python3 -c "
import random
random.seed(42)
seq = ''.join(random.choices(['A', 'C', 'G', 'T'], k=105500))
with open('/app/genome.txt', 'w') as f:
    f.write(seq)
"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
