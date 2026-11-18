#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr fonts-liberation
    pip3 install pytest Pillow pytesseract

    mkdir -p /app/messy_project
    touch /app/messy_project/script.py
    touch /app/messy_project/notes.md
    touch /app/messy_project/photo.jpg
    echo "[2023-01-01 12:00:00] Error occurred" > /app/messy_project/app.txt

    convert -background white -fill black -pointsize 18 label:"Rules:\n- Images (.png, .jpg) -> /media/images/\n- Documents (.pdf, .md) -> /docs/\n- Logs (.txt) -> /logs/ (Convert to JSON: {\"time\": \"...\", \"msg\": \"...\"})\n- Code (.py, .sh) -> /src/" /app/schema.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
