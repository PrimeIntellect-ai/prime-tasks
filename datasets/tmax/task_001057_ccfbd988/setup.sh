#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr libtesseract-dev imagemagick g++ fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create policy image
    convert -size 400x150 xc:white -font DejaVu-Sans -pointsize 20 -fill black -draw "text 10,30 'POLICY STRICT MODE' text 10,60 'FORBIDDEN_WORD: drop_database' text 10,90 'MIN_LENGTH: 10'" /app/policy.png

    # Generate RLE patches
    python3 -c '
def encode_rle(text, filename):
    with open(filename, "wb") as f:
        for char in text:
            f.write(bytes([1, ord(char)]))

encode_rle("config_update_v1_allowed", "/app/corpus/clean/clean1.patch")
encode_rle("set_value=1234567890", "/app/corpus/clean/clean2.patch")
encode_rle("drop_database_now", "/app/corpus/evil/evil1.patch")
encode_rle("short", "/app/corpus/evil/evil2.patch")
with open("/app/corpus/evil/evil3.patch", "wb") as f:
    f.write(bytes([1, 65, 2]))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
