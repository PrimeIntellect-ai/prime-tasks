#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        fonts-liberation \
        libtesseract-dev

    pip3 install pytest Pillow pytesseract

    mkdir -p /app
    mkdir -p /home/user

    # Create the oracle processor
    cat << 'EOF' > /app/oracle_processor.py
import sys
import re
from datetime import datetime, timedelta

def main():
    line = sys.stdin.read().strip()
    pattern = r'^\[(?P<start>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\] TO \[(?P<end>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\] VALUE: (?P<val>-?\d+\.\d+) STATUS: (?P<status>[A-Z]+)$'

    match = re.match(pattern, line)
    if not match:
        print("INVALID_FORMAT")
        return

    start_str = match.group('start')
    end_str = match.group('end')
    val = match.group('val')
    status = match.group('status')

    try:
        start_dt = datetime.strptime(start_str, '%Y-%m-%dT%H:%M:%S')
        end_dt = datetime.strptime(end_str, '%Y-%m-%dT%H:%M:%S')
    except ValueError:
        print("INVALID_FORMAT")
        return

    if end_dt < start_dt:
        print("INVALID_FORMAT")
        return

    curr_dt = start_dt
    while curr_dt <= end_dt:
        print(f"{curr_dt.strftime('%Y-%m-%dT%H:%M:%S')}|{val}|{status}")
        curr_dt += timedelta(seconds=1)

if __name__ == "__main__":
    main()
EOF

    # Generate the image
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw, ImageFont
import os

text = r'''REGEX PATTERN: ^\[(?P<start>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\] TO \[(?P<end>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\] VALUE: (?P<val>-?\d+\.\d+) STATUS: (?P<status>[A-Z]+)$
GAP-FILL RULE: Generate one record per second from start to end (inclusive).
OUTPUT FORMAT: {timestamp}|{val}|{status}'''

img = Image.new('RGB', (2500, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf", 24)
except:
    font = ImageFont.load_default()

d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save('/app/config_rules.png')
EOF
    python3 /tmp/gen_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
