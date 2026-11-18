#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick file
    pip3 install pytest

    mkdir -p /app

    # Create the instructions.png file
    convert -background white -fill black -pointsize 24 label:"PREFIX_ALL_FILES: DOC_\nREPLACE_TEXT: 'DRAFT_STATE' to 'PUBLISHED'" /app/instructions.png

    # Create the zip file with python
    cat << 'EOF' > /tmp/create_zip.py
import zipfile

with zipfile.ZipFile('/app/docs_update.zip', 'w') as zf:
    zf.writestr('../../etc/evil.txt', 'DRAFT_STATE document')
    zf.writestr('valid_doc.md', 'This is in DRAFT_STATE.')
    # Minimal valid PNG
    png_data = b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82'
    zf.writestr('image_file', png_data)
EOF
    python3 /tmp/create_zip.py
    rm /tmp/create_zip.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
