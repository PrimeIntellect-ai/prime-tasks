#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr libtesseract-dev
    pip3 install pytest Pillow

    mkdir -p /app/corpus

    # Create the image with the secret word
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color='white')
d = ImageDraw.Draw(img)
d.text((50, 80), "OVERLORD", fill='black')
img.save('/app/attacker_note.png')
EOF
    python3 /tmp/make_image.py
    rm /tmp/make_image.py

    # Create the corpora using printf to avoid Apptainer parsing % as sections
    printf "%s\n" \
        "../../../etc/passwd" \
        "%2e%2e%2f" \
        "/absolute/path" \
        "....//....//" \
        "..%252f" \
        "foo/bar/../../../bin/sh" \
        "%00.jpg" \
        "..%c0%af" \
        "%252e%252e%252f" \
        "C:\\Windows\\System32\\cmd.exe" \
        "..\\..\\..\\windows\\win.ini" \
        "null%00byte.txt" \
        > /app/corpus/evil.txt

    printf "%s\n" \
        "image.png" \
        "report_2024.pdf" \
        "valid-name.txt" \
        "foo.bar" \
        "a.txt" \
        > /app/corpus/clean.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
