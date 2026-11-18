#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang imagemagick
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create the formula image
    convert -background white -fill black -pointsize 48 label:"DAMPING = 0.0005" /app/formula.png

    # Generate clean and evil matrices
    python3 -c "
import csv
import random

# Generate clean matrices (positive definite)
for i in range(5):
    size = 4
    matrix = [[0.0]*size for _ in range(size)]
    for r in range(size):
        for c in range(size):
            if r == c:
                matrix[r][c] = 10.0 + random.random()
            else:
                val = random.random()
                matrix[r][c] = val
                matrix[c][r] = val
    with open(f'/app/corpus/clean/mat_{i}.csv', 'w', newline='') as f:
        csv.writer(f).writerows(matrix)

# Generate evil matrices (not positive definite)
for i in range(5):
    size = 4
    matrix = [[0.0]*size for _ in range(size)]
    for r in range(size):
        for c in range(size):
            if r == c:
                matrix[r][c] = -10.0 - random.random()
            else:
                val = random.random()
                matrix[r][c] = val
                matrix[c][r] = val
    with open(f'/app/corpus/evil/mat_{i}.csv', 'w', newline='') as f:
        csv.writer(f).writerows(matrix)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
