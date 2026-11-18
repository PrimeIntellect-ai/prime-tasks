#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
pip3 install pytest numpy pandas scikit-learn pillow pytesseract

mkdir -p /app

cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd
from PIL import Image, ImageDraw, ImageFont

# Generate settings image
img = Image.new('RGB', (300, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), "outlier_z_threshold = 2.0", fill=(0, 0, 0))
img.save('/app/settings.png')

# Generate dataset
np.random.seed(42)
n_samples = 500
n_features = 20

X = np.random.randn(n_samples, n_features)
# Add structure for similarity
X[:100] += np.random.randn(1, n_features) * 2

# Add outliers
for _ in range(50):
    i = np.random.randint(0, n_samples)
    j = np.random.randint(0, n_features)
    X[i, j] = np.random.choice([1, -1]) * np.random.uniform(5.0, 10.0)

# Add missing values
for _ in range(200):
    i = np.random.randint(0, n_samples)
    j = np.random.randint(0, n_features)
    X[i, j] = np.nan

df = pd.DataFrame(X, columns=[f'f{i+1}' for i in range(n_features)])
df.insert(0, 'id', range(n_samples))
df.to_csv('/app/dataset.csv', index=False)
EOF

python3 /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
