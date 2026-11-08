#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc imagemagick tesseract-ocr curl fonts-liberation
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create the image fixture
    convert -background white -fill black -font Courier -pointsize 36 label:"MOTIF: TACCATGC" /app/motif_reference.png || convert -background white -fill black -pointsize 36 label:"MOTIF: TACCATGC" /app/motif_reference.png

    # Create the target sequence data
    python3 -c '
import random
random.seed(42)
bases = ["A", "C", "G", "T"]
seq = [random.choice(bases) for _ in range(100000)]
motif = "TACCATGC" # length 8
# Embed perfect match at index 42000
for i, c in enumerate(motif):
    seq[42000 + i] = c
# Write to file
with open("/home/user/target.txt", "w") as f:
    f.write("".join(seq))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
