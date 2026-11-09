#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pandas numpy scikit-learn Pillow pytesseract

    mkdir -p /app/corpora/clean /app/corpora/evil

    python3 -c '
import numpy as np
import pandas as pd
from PIL import Image, ImageDraw
import os

os.makedirs("/app/corpora/clean", exist_ok=True)
os.makedirs("/app/corpora/evil", exist_ok=True)

# Generate Image
img = Image.new("RGB", (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "BASELINE CONFIGURATION:\nModel: Ridge(alpha=0.5)\nMax_Corr: 0.85\nMin_MSE: 0.12"
d.text((10,10), text, fill=(0,0,0))
img.save("/app/experiment_spec.png")

# Generate Clean Datasets (10)
# Low correlation, MSE >= 0.12
for i in range(10):
    np.random.seed(i)
    X = np.random.randn(100, 3)
    y = X[:, 0] + np.random.randn(100) * 0.6 # noise ensures MSE >= 0.12
    df = pd.DataFrame(X, columns=["f1", "f2", "f3"])
    df["target"] = y
    df.to_csv(f"/app/corpora/clean/data_{i}.csv", index=False)

# Generate Evil Datasets (10)
# 5 with high correlation
for i in range(5):
    np.random.seed(100+i)
    X = np.random.randn(100, 3)
    X[:, 1] = X[:, 0] * 0.9 + np.random.randn(100) * 0.05 # corr > 0.85
    y = X[:, 2] + np.random.randn(100) * 0.6
    df = pd.DataFrame(X, columns=["f1", "f2", "f3"])
    df["target"] = y
    df.to_csv(f"/app/corpora/evil/corr_{i}.csv", index=False)

# 5 with target leakage (MSE < 0.12)
for i in range(5):
    np.random.seed(200+i)
    X = np.random.randn(100, 3)
    y = X[:, 0] + np.random.randn(100) * 0.01 # very low noise, MSE < 0.12
    df = pd.DataFrame(X, columns=["f1", "f2", "f3"])
    df["target"] = y
    df.to_csv(f"/app/corpora/evil/leak_{i}.csv", index=False)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
