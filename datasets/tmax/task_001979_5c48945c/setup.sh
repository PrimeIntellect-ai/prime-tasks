#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr libtesseract-dev
    pip3 install pytest pandas numpy Pillow flask fastapi uvicorn pytesseract

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
from PIL import Image, ImageDraw
import os

os.makedirs('/app', exist_ok=True)

# Generate raw_data.csv
np.random.seed(42)
n_rows = 1000
df = pd.DataFrame({
    'alpha': np.random.normal(0.5, 1.0, n_rows),
    'beta': np.random.normal(50, 60, n_rows),
    'gamma': np.random.choice([0, 1, 2], n_rows),
    'target': np.random.normal(1.0, 2.0, n_rows)
})
df.to_csv('/app/raw_data.csv', index=False)

# Generate schema.png
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "VALIDATION RULES:\n1. alpha >= 0.0\n2. beta <= 100.0\n3. gamma in [0, 1]\n4. target > 0.0"
d.text((10,10), text, fill=(0,0,0))
img.save('/app/schema.png')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
