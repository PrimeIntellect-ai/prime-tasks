#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest numpy pandas pillow scipy pytesseract

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os
import csv
from PIL import Image, ImageDraw

os.makedirs('/app', exist_ok=True)

np.random.seed(42)
n = 100
x = np.random.uniform(-10, 10, n)
true_alpha = 1.6
true_beta = 1.9
y = true_beta * x + true_alpha + np.random.normal(0, 1, n)

with open('/app/data.csv', 'w') as f:
    writer = csv.writer(f)
    writer.writerow(['x', 'y'])
    for i in range(n):
        writer.writerow([x[i], y[i]])

A = np.array([[n + 4, np.sum(x)], [np.sum(x), np.sum(x**2) + 25]])
b = np.array([np.sum(y) + 6, np.sum(x*y) + 50])
alpha_map, beta_map = np.linalg.solve(A, b)

with open('/app/oracle_predict', 'w') as f:
    f.write('#!/usr/bin/env python3\n')
    f.write('import sys\n')
    f.write('x = float(sys.argv[1])\n')
    f.write(f'y = {beta_map} * x + {alpha_map}\n')
    f.write('print(f"{y:.4f}")\n')
os.chmod('/app/oracle_predict', 0o755)

img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "Priors:\nalpha ~ Normal(1.5, 0.5)\nbeta ~ Normal(2.0, 0.2)"
d.text((10,10), text, fill=(0,0,0))
img.save('/app/equation_params.png')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
