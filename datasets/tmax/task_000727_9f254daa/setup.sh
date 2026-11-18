#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest numpy scipy Pillow pytesseract

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

# 1. Generate the specification image
img = Image.new('RGB', (500, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "Data Filter Specs:\nMax absolute correlation: 0.75\nMean t-test p-value threshold: 0.01"
# Fallback to default font
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/spec_chart.png')

# 2. Generate clean corpus
np.random.seed(42)
for i in range(20):
    # Mean exactly around 0, low correlation.
    # N=1000 samples, D=5 features
    data = np.random.normal(0, 1, (1000, 5))
    np.save(f'/app/corpus/clean/clean_{i}.npy', data)

# 3. Generate evil corpus (Correlation violation)
for i in range(10):
    data = np.random.normal(0, 1, (1000, 5))
    # Artificially inject correlation > 0.75
    # correlation between feature 0 and 1 will be around 0.85
    data[:, 1] = data[:, 0] * 0.85 + np.random.normal(0, 0.4, 1000)
    np.save(f'/app/corpus/evil/evil_corr_{i}.npy', data)

# 4. Generate evil corpus (Mean violation)
for i in range(10):
    data = np.random.normal(0, 1, (1000, 5))
    # Shift mean so p-value of t-test < 0.01
    # For N=1000, standard error is ~0.031. A shift of 0.15 is roughly 4.8 standard errors (p < 0.0001).
    data[:, 3] += 0.15
    np.save(f'/app/corpus/evil/evil_mean_{i}.npy', data)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
