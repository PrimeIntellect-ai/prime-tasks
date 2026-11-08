#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-venv tesseract-ocr
pip3 install pytest numpy Pillow

mkdir -p /app

cat << 'EOF' > /tmp/setup.py
import numpy as np
import os
from PIL import Image, ImageDraw, ImageFont

os.makedirs('/app', exist_ok=True)

# Generate collinear dataset
np.random.seed(42)
N_train, N_test, D = 80, 200, 15

# Create a low rank covariance matrix
base_vectors = np.random.randn(D, 3)
true_cov = base_vectors @ base_vectors.T + 1e-4 * np.eye(D)
true_mean = np.random.randn(D)

X = np.random.multivariate_normal(true_mean, true_cov, N_train + N_test)
X_train = X[:N_train]
X_test = X[N_train:]

np.save('/app/train_data.npy', X_train)
np.save('/app/test_data.npy', X_test)

# Generate image fixture
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
draw = ImageDraw.Draw(img)
draw.text((10, 40), "Tikhonov parameter: lambda = 0.035", fill=(0,0,0))
img.save('/app/reg_param.png')
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
