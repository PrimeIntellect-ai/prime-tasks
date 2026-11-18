#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-pil \
        ffmpeg \
        tesseract-ocr \
        gcc \
        fonts-liberation

    pip3 install pytest

    mkdir -p /app

    # Create traffic_analyzer binary
    cat << 'EOF' > /tmp/ta.c
#include <stdio.h>
int main() {
    const char* p1 = "redirect=(http|https)://[^ ]+";
    const char* p2 = "bypassing CSP";
    printf("Traffic Analyzer v1.0\n");
    return 0;
}
EOF
    gcc -o /app/traffic_analyzer /tmp/ta.c
    rm /tmp/ta.c

    # Generate video frames with python
    cat << 'EOF' > /tmp/gen_frames.py
from PIL import Image, ImageDraw, ImageFont
import os
import random

os.makedirs('/tmp/frames', exist_ok=True)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf", 16)
except:
    font = ImageFont.load_default()

malicious = '192.168.1.1 GET /login?redirect=http://malicious.example.com missing CSP-Report-Only bypassing CSP'
normal = '192.168.1.2 GET /index.html 200'

lines = [malicious] * 42 + [normal] * 20
random.shuffle(lines)

frame_idx = 0
for i in range(0, len(lines), 15):
    img = Image.new('RGB', (1280, 720), color='black')
    d = ImageDraw.Draw(img)
    y = 20
    for line in lines[i:i+15]:
        d.text((20, y), line, font=font, fill=(255, 255, 255))
        y += 40
    img.save(f'/tmp/frames/frame_{frame_idx:03d}.png')
    frame_idx += 1
EOF
    python3 /tmp/gen_frames.py

    # Create video from frames
    ffmpeg -framerate 1 -i /tmp/frames/frame_%03d.png -c:v libx264 -r 30 -pix_fmt yuv420p /app/incident_capture.mp4
    rm -rf /tmp/frames /tmp/gen_frames.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
