#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Generate the runbook scan image
    convert -background white -fill black -font DejaVu-Sans -pointsize 18 label:"Legacy Verification Algorithm: Take the input string.\nReverse the entire string. For each character in the\nreversed string, get its ASCII integer value, add 12 to it,\nand join all the resulting numbers with underscores (_)." /app/runbook_scan.png

    # Create the oracle script
    cat << 'EOF' > /app/oracle_verify_header.py
import sys

def process(text):
    reversed_text = text[::-1]
    res = []
    for c in reversed_text:
        res.append(str(ord(c) + 12))
    return "_".join(res)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(process(sys.argv[1]))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
