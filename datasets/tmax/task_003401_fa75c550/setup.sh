#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip r-base tesseract-ocr libtesseract-dev
    pip3 install pytest numpy pandas Pillow scikit-learn pytesseract

    # Create the required files
    mkdir -p /app
    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd
from PIL import Image, ImageDraw
import os

os.makedirs('/app', exist_ok=True)

# 1. Generate Dataset
np.random.seed(42)
n_samples = 1000
X = np.random.randn(n_samples, 10)
y = 3.0 * X[:, 1] - 1.5 * X[:, 3] + 2.0 * X[:, 4] + 0.8 * X[:, 7] + np.random.randn(n_samples) * 0.5

columns = [f'f{i+1}' for i in range(10)]
df = pd.DataFrame(X, columns=columns)
df['y'] = y
df.to_csv('/app/data.csv', index=False)

# 2. Generate Image
img = Image.new('RGB', (400, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = "EXPERIMENT TRACKING DASHBOARD\nRun ID: 8932a\nModel: Ridge Regression\nAlpha: 0.5\nFeatures Used: f2, f4, f5, f8\nEnv: OMP_NUM_THREADS=1"
d.text((10,10), text, fill=(0,0,0))
img.save('/app/dashboard_screenshot.png')
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
