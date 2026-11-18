#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest numpy pytesseract Pillow

    mkdir -p /app

    # Generate the substitution matrix image
    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw, ImageFont
import os

text = """   A  C  G  T
A  5 -1 -2 -1
C -1  5 -3 -2
G -2 -3  5 -2
T -1 -2 -2  5"""

img = Image.new('RGB', (200, 150), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), text, fill=(0,0,0))
img.save('/app/substitution_matrix.png')
EOF
    python3 /tmp/make_image.py

    # Create the oracle script
    cat << 'EOF' > /app/oracle_prep_features
#!/usr/bin/env python3
import sys
import numpy as np

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    seq1 = sys.argv[1]
    seq2 = sys.argv[2]

    matrix = {
        'A': {'A': 5, 'C': -1, 'G': -2, 'T': -1},
        'C': {'A': -1, 'C': 5, 'G': -3, 'T': -2},
        'G': {'A': -2, 'C': -3, 'G': 5, 'T': -2},
        'T': {'A': -1, 'C': -2, 'G': -2, 'T': 5}
    }

    length = len(seq1)
    score = 0
    matches = 0
    gc1 = sum(1 for c in seq1 if c in 'GC') / length
    gc2 = sum(1 for c in seq2 if c in 'GC') / length

    for c1, c2 in zip(seq1, seq2):
        score += matrix[c1][c2]
        if c1 == c2:
            matches += 1

    match_prop = matches / length
    score_prop = score / (length * 5)

    M = np.array([
        [gc1 + 0.01, match_prop],
        [score_prop, gc2 + 0.01]
    ])

    det = np.linalg.det(M)

    print(f"Score: {score}, Det: {det:.4f}")

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_prep_features

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
