#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pandas numpy scikit-learn joblib Pillow pytesseract

    # Create setup script
    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
from sklearn.datasets import make_classification
import os
from PIL import Image, ImageDraw

# Generate data
X, y = make_classification(n_samples=2000, n_features=20, n_informative=15, random_state=42)
uuids = [f"id_{i}" for i in range(2000)]

df_A = pd.DataFrame(X[:, :10], columns=[f"feat_{i}" for i in range(10)])
df_A['uuid'] = uuids

df_B = pd.DataFrame(X[:, 10:], columns=[f"feat_{i}" for i in range(10, 20)])
df_B['uuid'] = uuids

df_y = pd.DataFrame({'label': y, 'uuid': uuids})

os.makedirs('/home/user/data', exist_ok=True)
df_A.to_csv('/home/user/data/features_A.csv', index=False)
df_B.to_csv('/home/user/data/features_B.csv', index=False)
df_y.to_csv('/home/user/data/labels.csv', index=False)

# Generate image
os.makedirs('/app', exist_ok=True)
img = Image.new('RGB', (800, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "Use the following for the MLP: hidden_layer_sizes=(128, 64), activation='relu', alpha=0.05"
d.text((10, 40), text, fill=(0, 0, 0))
img.save('/app/arch.png')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
