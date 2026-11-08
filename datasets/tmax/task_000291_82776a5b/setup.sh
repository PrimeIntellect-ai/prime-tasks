#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        ffmpeg \
        tesseract-ocr \
        tesseract-ocr-eng \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app/frames
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate video frames
    convert -size 200x200 xc:white -font DejaVu-Sans -pointsize 100 -fill black -gravity center -draw "text 0,0 'X'" /app/frames/0.png
    convert -size 200x200 xc:white -font DejaVu-Sans -pointsize 100 -fill black -gravity center -draw "text 0,0 '7'" /app/frames/1.png
    convert -size 200x200 xc:white -font DejaVu-Sans -pointsize 100 -fill black -gravity center -draw "text 0,0 'K'" /app/frames/2.png
    convert -size 200x200 xc:white -font DejaVu-Sans -pointsize 100 -fill black -gravity center -draw "text 0,0 '9'" /app/frames/3.png

    ffmpeg -framerate 1 -i /app/frames/%d.png -c:v libx264 -r 1 -pix_fmt yuv420p /app/salt_video.mp4

    # Generate corpora
    python3 -c '
import os
import hashlib

salt = "X7K9"

def md5(s):
    return hashlib.md5(s.encode()).hexdigest()

# Clean
for i in range(10):
    url = f"/api/v1/users?id={i}"
    chk = md5(url + salt)
    with open(f"/app/corpus/clean/clean_{i:02d}.patch", "w") as f:
        f.write(f"--- a/routes.conf\n+++ b/routes.conf\n@@ -0,0 +1 @@\n++ROUTE {url} CHECKSUM={chk}\n")

# Evil - invalid checksum
for i in range(5):
    url = f"/api/v1/users?id={i+10}"
    chk = md5("wrong")
    with open(f"/app/corpus/evil/evil_inv_{i:02d}.patch", "w") as f:
        f.write(f"--- a/routes.conf\n+++ b/routes.conf\n@@ -0,0 +1 @@\n++ROUTE {url} CHECKSUM={chk}\n")

# Evil - valid checksum, NOP sled
for i in range(5):
    url = f"/api/v1/exec?cmd=%90%90%90%31%c0&id={i}"
    chk = md5(url + salt)
    with open(f"/app/corpus/evil/evil_nop_{i:02d}.patch", "w") as f:
        f.write(f"--- a/routes.conf\n+++ b/routes.conf\n@@ -0,0 +1 @@\n++ROUTE {url} CHECKSUM={chk}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
