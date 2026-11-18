#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick
    pip3 install pytest Pillow pytesseract

    mkdir -p /app

    # Generate the console panic image
    convert -background black -fill white -pointsize 24 label:"CRITICAL PANIC: VFS sync failed. INGESTION_OFFSET=137" /app/console_panic.png

    # Create the oracle processor
    cat << 'EOF' > /app/oracle_processor
#!/usr/bin/env python3
import sys

def process(hex_str):
    offset = 137
    res = []
    for i in range(0, len(hex_str), 2):
        b = int(hex_str[i:i+2], 16)
        res.append(f"{(b ^ offset) & 0xFF:02X}")
    return "".join(res)

if __name__ == '__main__':
    if len(sys.argv) > 1:
        print(process(sys.argv[1]))
EOF
    chmod +x /app/oracle_processor

    # Create the user and home directory
    useradd -m -s /bin/bash user || true

    # Create the buggy processor
    cat << 'EOF' > /home/user/processor.py
import sys
import os

def process(hex_str):
    offset = int(os.environ.get('INGESTION_OFFSET', '0'))
    res = []
    for i in range(0, len(hex_str), 2):
        try:
            b = int(hex_str[i:i+2], 16)
            # Bug: incorrect bitwise operation and mask
            res.append(f"{(b | offset) & 0x7F:02X}")
        except ValueError:
            pass
    return "".join(res)

if __name__ == '__main__':
    if len(sys.argv) > 1:
        print(process(sys.argv[1]))
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
