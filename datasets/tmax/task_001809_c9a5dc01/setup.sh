#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest h5py numpy Pillow

    mkdir -p /app/simulations/clean
    mkdir -p /app/simulations/evil

    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), 'Gradient threshold: 42.5', fill=(0, 0, 0))
img.save('/app/threshold_note.png')

import h5py
import numpy as np

# Clean files (gradient <= 42.5, no NaNs/Infs)
with h5py.File('/app/simulations/clean/clean1.h5', 'w') as f:
    f.create_dataset('density', data=np.linspace(0, 100, 100))
with h5py.File('/app/simulations/clean/clean2.h5', 'w') as f:
    f.create_dataset('density', data=np.array([10.0, 50.0, 90.0, 130.0]))

# Evil files
# 1. Contains NaN
with h5py.File('/app/simulations/evil/evil1.h5', 'w') as f:
    f.create_dataset('density', data=np.array([10.0, np.nan, 20.0]))
# 2. Contains Inf
with h5py.File('/app/simulations/evil/evil2.h5', 'w') as f:
    f.create_dataset('density', data=np.array([10.0, np.inf, 20.0]))
# 3. Gradient > 42.5
with h5py.File('/app/simulations/evil/evil3.h5', 'w') as f:
    f.create_dataset('density', data=np.array([10.0, 60.0, 20.0]))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
