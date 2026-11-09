#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pandas numpy scipy pillow pytesseract

    mkdir -p /app/training_data/clean
    mkdir -p /app/training_data/anomalous
    mkdir -p /app/test_corpus/clean
    mkdir -p /app/test_corpus/evil

    cat << 'EOF' > /app/generate_data.py
import os
import numpy as np
import pandas as pd
from PIL import Image, ImageDraw

# Generate image
img = Image.new('RGB', (400, 150), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "BASELINE PRIORS\nSensor_A: mu=12.5, sigma=1.5\nSensor_B: mu=-4.2, sigma=0.8\nSensor_C: mu=100.0, sigma=5.0"
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/sensor_priors.png')

def generate_batch(path, is_evil):
    os.makedirs(path, exist_ok=True)
    n = 100
    ids = np.arange(1, n + 1)

    mu_a, sig_a = 12.5, 1.5
    mu_b, sig_b = -4.2, 0.8
    mu_c, sig_c = 100.0, 5.0

    if is_evil:
        sensor_to_shift = np.random.choice(['A', 'B', 'C'])
        if sensor_to_shift == 'A':
            mu_a += 3 * sig_a
        elif sensor_to_shift == 'B':
            mu_b += 3 * sig_b
        else:
            mu_c += 3 * sig_c

    a = np.random.normal(mu_a, sig_a, n)
    b = np.random.normal(mu_b, sig_b, n)
    c = np.random.normal(mu_c, sig_c, n)

    readings = pd.DataFrame({'id': ids, 'Sensor_A': a, 'Sensor_B': b})
    metadata = pd.DataFrame({'id': ids, 'Sensor_C': c})

    readings.to_csv(os.path.join(path, 'readings.csv'), index=False)
    metadata.to_csv(os.path.join(path, 'metadata.csv'), index=False)

# Train clean
for i in range(10):
    generate_batch(f'/app/training_data/clean/batch_{i}', False)

# Train anomalous
for i in range(10):
    generate_batch(f'/app/training_data/anomalous/batch_{i}', True)

# Test clean
for i in range(50):
    generate_batch(f'/app/test_corpus/clean/batch_{i}', False)

# Test evil
for i in range(50):
    generate_batch(f'/app/test_corpus/evil/batch_{i}', True)
EOF

    python3 /app/generate_data.py
    rm /app/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
