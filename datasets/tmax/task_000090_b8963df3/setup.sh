#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        fonts-dejavu-core \
        cargo \
        tesseract-ocr \
        libtesseract-dev

    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate dashboard.mp4 with the text on frame 42
    ffmpeg -f lavfi -i "color=c=white:s=640x480:d=2" -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:fontsize=30:fontcolor=black:x=(w-text_w)/2:y=(h-text_h)/2:text='ALERT_CONFIG\: W=8s, T=12':enable='between(n,42,42)'" -c:v libx264 -pix_fmt yuv420p /app/dashboard.mp4

    # Generate logs
    python3 -c '
import os
os.makedirs("/app/corpora/clean", exist_ok=True)
os.makedirs("/app/corpora/evil", exist_ok=True)

# Clean 1: 12 failures in 8 seconds (threshold is >12 in 8s)
with open("/app/corpora/clean/log1.txt", "w") as f:
    for i in range(12):
        f.write(f"[{1000 + i}] WARNING Failed authentication for user admin from 10.0.0.1\n")

# Clean 2: 13 failures in 9 seconds (not within 8s)
with open("/app/corpora/clean/log2.txt", "w") as f:
    for i in range(13):
        f.write(f"[{1000 + int(i * 9 / 12)}] WARNING Failed authentication for user admin from 10.0.0.2\n")

# Evil 1: 13 failures in 8 seconds (13 > 12 within 8s)
with open("/app/corpora/evil/log1.txt", "w") as f:
    for i in range(13):
        f.write(f"[{1000 + int(i * 8 / 12)}] WARNING Failed authentication for user admin from 10.0.0.3\n")

# Evil 2: 15 failures in 5 seconds
with open("/app/corpora/evil/log2.txt", "w") as f:
    for i in range(15):
        f.write(f"[{2000 + int(i * 5 / 14)}] WARNING Failed authentication for user root from 10.0.0.4\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
