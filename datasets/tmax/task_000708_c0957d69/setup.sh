#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow numpy pandas scipy

    mkdir -p /app
    mkdir -p /opt/corpus/clean
    mkdir -p /opt/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
import pandas as pd
from PIL import Image, ImageDraw

# Create image
img = Image.new('RGB', (600, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), "MINIMUM ACCEPTABLE CORRELATION: 0.82", fill=(0, 0, 0))
img.save('/app/specs.png')

# Create datasets
np.random.seed(42)

def make_data(path, corr):
    os.makedirs(path, exist_ok=True)
    cov = [[1.0, corr], [corr, 1.0]]
    data = np.random.multivariate_normal([0, 0], cov, size=100)

    df1 = pd.DataFrame({'user_id': range(1, 101), 'metric_x': data[:, 0]})
    df2 = pd.DataFrame({'user_id': range(1, 101), 'metric_y': data[:, 1]})

    df2 = df2.sample(frac=1).reset_index(drop=True)

    df1.to_csv(os.path.join(path, 'table1.csv'), index=False)
    df2.to_csv(os.path.join(path, 'table2.csv'), index=False)

make_data('/opt/corpus/clean/clean_01', 0.95)
make_data('/opt/corpus/clean/clean_02', 0.85)
make_data('/opt/corpus/evil/evil_01', 0.50)
make_data('/opt/corpus/evil/evil_02', 0.80)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
