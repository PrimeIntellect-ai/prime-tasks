#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang-go
    pip3 install --default-timeout=100 pytest Pillow numpy

    mkdir -p /app
    mkdir -p /home/user/sample_data
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = 'EQUIPMENT CALIBRATION LOG\nMesh refinement parameter R=4\nBase carrier frequency fc=500Hz\nCheck sensor offsets.'
d.text((10,10), text, fill=(0,0,0))
img.save('/app/calibration_note.png')

import numpy as np
import os

fs = 2000
t = np.arange(0, 1.0, 1/fs)

clean_sig = np.sin(2 * np.pi * 500 * t) + np.random.normal(0, 0.05, len(t))
evil_sig = np.sin(2 * np.pi * 500 * t) + 0.8 * np.sin(2 * np.pi * 800 * t) + np.random.normal(0, 0.05, len(t))

np.savetxt('/home/user/sample_data/sample_clean.csv', np.column_stack((t, clean_sig)), delimiter=',', fmt='%.6f')
np.savetxt('/home/user/sample_data/sample_evil.csv', np.column_stack((t, evil_sig)), delimiter=',', fmt='%.6f')

for i in range(5):
    c_sig = np.sin(2 * np.pi * 500 * t) + np.random.normal(0, 0.05, len(t))
    np.savetxt(f'/app/corpus/clean/clean_{i}.csv', np.column_stack((t, c_sig)), delimiter=',', fmt='%.6f')

    e_sig = np.sin(2 * np.pi * 500 * t) + 0.8 * np.sin(2 * np.pi * 800 * t) + np.random.normal(0, 0.05, len(t))
    np.savetxt(f'/app/corpus/evil/evil_{i}.csv', np.column_stack((t, e_sig)), delimiter=',', fmt='%.6f')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
