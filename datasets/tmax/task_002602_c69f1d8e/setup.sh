#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        gcc \
        imagemagick \
        fonts-dejavu-core

    pip3 install pytest numpy

    mkdir -p /app/clean /app/evil

    # Generate the reference image using ImageMagick
    # Fix ImageMagick policy to allow drawing text if needed, but usually fine for simple text
    convert -size 800x300 canvas:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,40 'TARGET REFERENCE EMBEDDING\n0.500, -0.200, 0.100, 0.800, 0.250\n\nREJECTION CRITERIA\nCosine Similarity >= 0.85'" /app/reference_spec.png

    # Python script to generate the CSV corpora
    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np

os.makedirs('/app/clean', exist_ok=True)
os.makedirs('/app/evil', exist_ok=True)

ref_vec = np.array([0.500, -0.200, 0.100, 0.800, 0.250])
ref_norm = np.linalg.norm(ref_vec)

def generate_row(is_evil=False):
    while True:
        row = np.random.randn(5)
        row_norm = np.linalg.norm(row)
        sim = np.dot(row, ref_vec) / (row_norm * ref_norm)
        if is_evil and sim >= 0.86:
            return row
        elif not is_evil and sim < 0.79:
            return row

for i in range(10):
    # Clean CSV
    with open(f'/app/clean/data_{i}.csv', 'w') as f:
        f.write('id,f1,f2,f3,f4,f5\n')
        for j in range(20):
            row = generate_row(is_evil=False)
            f.write(f"{j},{row[0]:.6f},{row[1]:.6f},{row[2]:.6f},{row[3]:.6f},{row[4]:.6f}\n")

    # Evil CSV
    with open(f'/app/evil/data_{i}.csv', 'w') as f:
        f.write('id,f1,f2,f3,f4,f5\n')
        evil_idx = np.random.randint(0, 20)
        for j in range(20):
            row = generate_row(is_evil=(j == evil_idx))
            f.write(f"{j},{row[0]:.6f},{row[1]:.6f},{row[2]:.6f},{row[3]:.6f},{row[4]:.6f}\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
