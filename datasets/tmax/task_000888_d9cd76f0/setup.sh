#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        libtesseract-dev \
        g++ \
        fonts-liberation

    pip3 install pytest Pillow

    mkdir -p /app/corpora/clean /app/corpora/evil /app/corpora_hidden/clean /app/corpora_hidden/evil

    python3 -c '
import os
from PIL import Image, ImageDraw, ImageFont

# Create image
img = Image.new("RGB", (600, 200), color="white")
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 30)
except:
    font = ImageFont.load_default()
d.text((20, 40), "TIMEOUT_THRESHOLD=25000.0\nMONTE_CARLO_RUNS=5000", fill="black", font=font)
img.save("/app/profile_specs.png")

# Create graphs
def create_clean(path):
    with open(path, "w") as f:
        f.write("5\n")
        f.write("10.0\n10.0\n10.0\n10.0\n0.0\n")
        f.write("0 1 1.0\n")
        f.write("1 2 0.5\n")
        f.write("1 3 0.5\n")
        f.write("2 4 1.0\n")
        f.write("3 4 1.0\n")

def create_evil(path):
    with open(path, "w") as f:
        f.write("5\n")
        f.write("1000.0\n1000.0\n1000.0\n1000.0\n0.0\n")
        f.write("0 1 1.0\n")
        f.write("1 2 0.99\n")
        f.write("1 4 0.01\n")
        f.write("2 1 1.0\n")
        f.write("3 4 1.0\n")

for d in ["/app/corpora/clean", "/app/corpora_hidden/clean"]:
    for i in range(5):
        create_clean(f"{d}/graph_{i}.txt")

for d in ["/app/corpora/evil", "/app/corpora_hidden/evil"]:
    for i in range(5):
        create_evil(f"{d}/graph_{i}.txt")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
