#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest numpy Pillow scipy scikit-learn

    mkdir -p /app

    python3 -c "
import numpy as np
from PIL import Image, ImageDraw

# Generate image
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = '''Target Motif Parameters:
State 1: Mean = 45.5 pA, StdDev = 5.0 pA, Weight = 0.5
State 2: Mean = 60.2 pA, StdDev = 4.2 pA, Weight = 0.5
Detection Threshold (W1): < 2.5'''
d.text((10,10), text, fill=(0,0,0))
img.save('/app/motif_spec.png')

# Generate signal
np.random.seed(42)
signal_len = 10000
signal = np.random.normal(50, 10, signal_len)

# Inject 50 motifs
indices = []
for i in range(50):
    idx = np.random.randint(0, signal_len - 100)
    indices.append(idx)

    # motif: length 100, mixture of two gaussians
    motif = np.zeros(100)
    for j in range(100):
        if np.random.rand() < 0.5:
            motif[j] = np.random.normal(45.5, 5.0)
        else:
            motif[j] = np.random.normal(60.2, 4.2)
    signal[idx:idx+100] = motif

indices.sort()

with open('/app/raw_signal.txt', 'w') as f:
    for val in signal:
        f.write(f'{val}\n')

with open('/app/ground_truth_indices.txt', 'w') as f:
    for idx in indices:
        f.write(f'{idx}\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
