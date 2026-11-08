#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr libtesseract-dev
    pip3 install pytest numpy pandas Pillow pytesseract scipy

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    python3 -c "
import os
import numpy as np
import pandas as pd
from PIL import Image, ImageDraw

text = '''Physical System Mode Constraints:
Eq 1: f(x,y) = x^3 - 3x - y = 0
Eq 2: g(x,y) = y^2 - x - 2 = 0
Root in quadrant I (x>0, y>0).
Precision matrix = Jacobian(f, g) at root.'''

img = Image.new('RGB', (800, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((20, 20), text, fill=(0, 0, 0))
img.save('/app/lab_notes.png')

np.random.seed(42)
mu_clean = [2, 2]
cov_clean = [[4/35, 1/35], [1/35, 9/35]]

for i in range(50):
    data = np.random.multivariate_normal(mu_clean, cov_clean, 1000)
    df = pd.DataFrame(data, columns=['x', 'y'])
    df.to_csv(f'/app/corpus/clean/trace_{i}.csv', index=False)

mu_evil1 = [2.5, 2.0]
cov_evil2 = [[0.2, 0.0], [0.0, 0.2]]

for i in range(50):
    if i < 25:
        data = np.random.multivariate_normal(mu_evil1, cov_clean, 1000)
    else:
        data = np.random.multivariate_normal(mu_clean, cov_evil2, 1000)
    df = pd.DataFrame(data, columns=['x', 'y'])
    df.to_csv(f'/app/corpus/evil/trace_{i}.csv', index=False)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
