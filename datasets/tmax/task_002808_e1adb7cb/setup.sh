#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core

    pip3 install --default-timeout=100 pytest pytesseract Pillow

    mkdir -p /app

    # Create the oracle script
    cat << 'EOF' > /app/oracle_etl_cleaner.py
#!/usr/bin/env python3
import sys

invalid = {"NULL", "N/A", "UNKNOWN", "ERR", "DROP"}
threshold = 4.5

for line in sys.stdin:
    tokens = line.strip().split()
    valid_tokens = [t for t in tokens if t not in invalid]
    if not valid_tokens:
        print("REJECTED")
        continue
    avg_len = sum(len(t) for t in valid_tokens) / len(valid_tokens)
    if avg_len >= threshold:
        print(" ".join(valid_tokens))
    else:
        print("REJECTED")
EOF
    chmod +x /app/oracle_etl_cleaner.py

    # Generate the configuration image
    convert -background white -fill black -font DejaVu-Sans -pointsize 24 label:"INVALID_TOKENS: NULL, N/A, UNKNOWN, ERR, DROP\nTHRESHOLD: 4.5" /app/config_image.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
