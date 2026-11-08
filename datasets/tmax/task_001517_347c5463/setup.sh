#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang-go
    pip3 install --no-cache-dir pytest numpy pandas Pillow scikit-learn

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd
from PIL import Image, ImageDraw
import os

os.makedirs('/app', exist_ok=True)

# 1. Generate Image
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = """Data Cleaning Rules:
- F2: Drop row if > 10.0
- F4: Drop row if < 0.0
- Imputation: Column Mean
- Target Dimensions: 2
"""
d.text((10,10), text, fill=(0,0,0))
img.save('/app/guidelines.png')

# 2. Generate Data
np.random.seed(42)
n_samples = 100

# Base features with correlation
f1 = np.random.normal(5, 2, n_samples)
f2 = f1 * 1.5 + np.random.normal(0, 1, n_samples)
f3 = -f1 * 0.8 + np.random.normal(0, 0.5, n_samples)
f4 = np.random.normal(10, 3, n_samples)

data = pd.DataFrame({'F1': f1, 'F2': f2, 'F3': f3, 'F4': f4})

# Inject Outliers
data.loc[5, 'F2'] = 15.2  # > 10.0
data.loc[25, 'F2'] = 11.1 # > 10.0
data.loc[50, 'F4'] = -2.5 # < 0.0

# Inject Missing Values
data.loc[10, 'F1'] = np.nan
data.loc[30, 'F3'] = np.nan
data.loc[80, 'F4'] = np.nan

data.to_csv('/app/data.csv', index=False)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/workspace
    chmod -R 777 /home/user
    chmod -R 777 /app
