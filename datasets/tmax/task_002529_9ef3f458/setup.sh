#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-liberation
    pip3 install pytest scikit-learn pandas numpy pillow pytesseract requests flask fastapi uvicorn

    mkdir -p /app

    python3 -c "
import pandas as pd
import numpy as np
from sklearn.datasets import make_classification
from PIL import Image, ImageDraw, ImageFont

# Generate dataset
X, y = make_classification(n_samples=200, n_features=10, n_informative=5, n_classes=2, random_state=42)
df = pd.DataFrame(X, columns=[f'f{i}' for i in range(1, 11)])
df['target'] = y
df.insert(0, 'id', range(1, 201))

# Inject missing values
np.random.seed(42)
for _ in range(20):
    row = np.random.randint(0, 200)
    col = np.random.randint(1, 11)
    df.iloc[row, col] = np.nan

df.to_csv('/app/data.csv', index=False)

# Generate image with hyperparameters
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = 'CV_FOLDS=3\nPCA_COMPONENTS=[2,3]\nK_NEIGHBORS=[3,5]'
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf', 24)
except IOError:
    font = ImageFont.load_default()
d.text((10, 10), text, fill=(0, 0, 0), font=font)
img.save('/app/hyperparameters.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
