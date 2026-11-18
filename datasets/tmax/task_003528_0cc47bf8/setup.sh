#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest h5py numpy Pillow pytesseract

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate the image and the HDF5 files
    python3 -c '
import os
import h5py
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Generate image
text = """System of Equations:
F1(x, y) = x**2 + y**2 - 4
F2(x, y) = x*y - 1

Convergence Criteria:
abs(F1) <= 1e-4
abs(F2) <= 1e-4
"""
img = Image.new("RGB", (400, 300), color="white")
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill="black")
img.save("/app/system_def.png")

# Generate clean HDF5 files
# Roots: x = sqrt(2 + sqrt(3)) ~ 1.93185165, y = 1/x ~ 0.51763809
root_x = np.sqrt(2 + np.sqrt(3))
root_y = 1 / root_x

for i in range(20):
    with h5py.File(f"/app/corpora/clean/clean_{i}.h5", "w") as f:
        x = np.random.rand(100)
        y = np.random.rand(100)
        x[-1] = root_x
        y[-1] = root_y
        f.create_dataset("x", data=x)
        f.create_dataset("y", data=y)

# Generate evil HDF5 files
for i in range(20):
    with h5py.File(f"/app/corpora/evil/evil_{i}.h5", "w") as f:
        x = np.random.rand(100)
        y = np.random.rand(100)
        if i % 3 == 0:
            x[-1] = np.nan
            y[-1] = np.nan
        elif i % 3 == 1:
            x[-1] = 0.0
            y[-1] = 0.0
        else:
            x[-1] = 10.0
            y[-1] = 10.0
        f.create_dataset("x", data=x)
        f.create_dataset("y", data=y)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
