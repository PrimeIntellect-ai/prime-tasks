#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc
pip3 install pytest pandas numpy Pillow

mkdir -p /app

cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np
from PIL import Image, ImageDraw

# Generate image
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), "12.5 45.2 8.9 101.3 55.0", fill=(0, 0, 0))
img.save('/app/target_item.png')

# Generate dataset
np.random.seed(42)
n_items = 1000
item_ids = np.arange(1, n_items + 1)
data = {
    'item_id': item_ids,
    'f1': np.random.uniform(0, 100, n_items),
    'f2': np.random.uniform(0, 100, n_items),
    'f3': np.random.uniform(0, 100, n_items),
    'f4': np.random.uniform(0, 200, n_items),
    'f5': np.random.uniform(0, 100, n_items)
}
df = pd.DataFrame(data)

# Introduce missing values
for col in ['f1', 'f2', 'f3', 'f4', 'f5']:
    mask = np.random.rand(n_items) < 0.1
    df.loc[mask, col] = np.nan

# Ensure target is close to some items
df.loc[0, ['f1', 'f2', 'f3', 'f4', 'f5']] = [12.6, 45.1, 9.0, 101.0, 55.2]
df.loc[1, ['f1', 'f2', 'f3', 'f4', 'f5']] = [12.4, 45.3, 8.8, 101.5, 54.9]

# Save to CSV
df.to_csv('/app/items.csv', index=False)
EOF

python3 /tmp/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
