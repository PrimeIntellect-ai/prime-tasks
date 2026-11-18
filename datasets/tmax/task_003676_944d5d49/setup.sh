#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr python3-pil
    pip3 install --default-timeout=100 pytest

    mkdir -p /app

    # Create the reference oracle
    cat << 'EOF' > /app/reference_sanitize_audit
#!/usr/bin/env python3
import sys
import re

def process(line):
    line = line.strip('\r\n')
    # Redact
    line = re.sub(r'(--db-pass=)(\S+)', r'\1[REDACTED]', line)
    # Flag
    if '<script>' in line or '; rm -rf' in line:
        line += ' [FLAG:INJECTION_XSS]'
    return line

if __name__ == '__main__':
    for input_line in sys.stdin:
        print(process(input_line))
EOF
    chmod +x /app/reference_sanitize_audit

    # Generate the video fixture
    cat << 'EOF' > /tmp/gen_frames.py
from PIL import Image, ImageDraw
import os

os.makedirs("/tmp/frames", exist_ok=True)
for i in range(300):
    img = Image.new('RGB', (800, 600), color='black')
    d = ImageDraw.Draw(img)
    if i < 100:
        text = "top"
    elif i < 147:  # 100 to 146 inclusive -> 47 frames
        text = "bash script.sh --db-pass=SuperSecret99"
    else:
        text = "tail -f /var/log/syslog"
    d.text((10, 20), text, fill=(255, 255, 255))
    img.save(f"/tmp/frames/frame_{i:03d}.png")
EOF
    python3 /tmp/gen_frames.py
    ffmpeg -framerate 10 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/incident_record.mp4
    rm -rf /tmp/frames /tmp/gen_frames.py

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
