#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install --default-timeout=100 pytest pandas numpy Pillow scikit-learn scipy flask fastapi uvicorn pytesseract requests

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np
from PIL import Image, ImageDraw
import os

os.makedirs('/app', exist_ok=True)

# Generate CSV
np.random.seed(10)
n_samples = 200
df_north = pd.DataFrame({
    'sensor_id': np.random.choice([1, 2], size=n_samples//2),
    'temp': np.random.normal(20, 2, n_samples//2),
    'pressure': np.random.normal(1013, 5, n_samples//2),
    'vibration': np.random.normal(0.5, 0.1, n_samples//2),
    'output_metric': np.random.normal(48.5, 3.0, n_samples//2)
})
df_south = pd.DataFrame({
    'sensor_id': np.random.choice([3, 4], size=n_samples//2),
    'temp': np.random.normal(25, 3, n_samples//2),
    'pressure': np.random.normal(1010, 4, n_samples//2),
    'vibration': np.random.normal(0.6, 0.2, n_samples//2),
    'output_metric': np.random.normal(52.1, 2.5, n_samples//2)
})
df = pd.concat([df_north, df_south])
df.to_csv('/app/sensor_readings.csv', index=False)

# Generate Image
text = "sensor_id,location\n1,North_Wing\n2,North_Wing\n3,South_Wing\n4,South_Wing"
img = Image.new('RGB', (300, 150), color='white')
d = ImageDraw.Draw(img)
d.text((10,10), text, fill=(0,0,0))
img.save('/app/sensor_metadata.png')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
