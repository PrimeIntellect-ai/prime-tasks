#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr g++ make
    pip3 install pytest pandas numpy Pillow

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_data.py
import pandas as pd
import numpy as np
from PIL import Image, ImageDraw

# Generate legacy metadata image
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "SYSTEM CONFIGURATION\n====================\nCRITICAL_ANOMALY_THRESHOLD=5\nTARGET_SENSOR=S07"
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/legacy_metadata.png')

# Generate sensor data CSV
np.random.seed(42)
timestamps = pd.date_range('2023-01-01', periods=1000, freq='S')
data = []

base_values = np.sin(np.linspace(0, 20, 1000)) + np.random.normal(0, 0.1, 1000)

for i in range(1, 11):
    sensor_id = f"S{i:02d}"
    if sensor_id == 'S07':
        values = base_values
    elif sensor_id == 'S04':
        # Highly correlated to S07
        values = base_values + np.random.normal(0, 0.05, 1000)
    elif sensor_id == 'S02':
        values = np.random.normal(5, 1, 1000)
        # Add exactly 6 anomalies
        anomaly_indices = np.random.choice(1000, 6, replace=False)
        for idx in anomaly_indices:
            values[idx] += 20  # Ensure it is > mean + 3*std
    else:
        values = np.random.normal(np.random.randint(1, 10), np.random.uniform(0.5, 2.0), 1000)

    df = pd.DataFrame({'timestamp': timestamps, 'sensor_id': sensor_id, 'value': values})
    data.append(df)

final_df = pd.concat(data).sort_values(by=['timestamp', 'sensor_id'])
final_df.to_csv('/app/sensor_data.csv', index=False)
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
