#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr cargo rustc
    pip3 install pytest Pillow numpy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup_data.py
import os
import numpy as np
from PIL import Image, ImageDraw

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

# Generate image
img = Image.new('RGB', (400, 100), color='white')
d = ImageDraw.Draw(img)
d.text((10,10), "EXPECTED_PEAK_CENTER: 450\nMAX_FWHM: 20", fill=(0,0,0))
img.save('/app/calibration_specs.png')

# Generate CSVs
def make_csv(filename, center, fwhm):
    x = np.linspace(400, 500, 1000)
    sigma = fwhm / 2.355
    y = 1.0 - 0.5 * np.exp(- (x - center)**2 / (2 * sigma**2))
    with open(filename, 'w') as f:
        f.write("wavelength,intensity\n")
        for xi, yi in zip(x, y):
            f.write(f"{xi:.4f},{yi:.4f}\n")

for i in range(20):
    center = np.random.uniform(446.0, 454.0)
    fwhm = np.random.uniform(10.0, 18.0)
    make_csv(f"/app/corpus/clean/clean_{i}.csv", center, fwhm)

for i in range(10):
    center = np.random.choice([np.random.uniform(400.0, 443.0), np.random.uniform(457.0, 500.0)])
    fwhm = np.random.uniform(10.0, 18.0)
    make_csv(f"/app/corpus/evil/evil_center_{i}.csv", center, fwhm)

for i in range(10):
    center = np.random.uniform(446.0, 454.0)
    fwhm = np.random.uniform(26.0, 40.0)
    make_csv(f"/app/corpus/evil/evil_fwhm_{i}.csv", center, fwhm)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
