#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pytesseract pandas pillow

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import os
import json
import pandas as pd
from PIL import Image, ImageDraw, ImageFont

# 1. Create Image
img = Image.new('RGB', (600, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = """Sensor_ID | Min_Val | Max_Val | Multiplier
ENV_A100  | -50.0   | 150.0   | 1.05
ENV_B200  | 0.0     | 500.0   | 0.98
ENV_C300  | -20.0   | 80.0    | 1.00"""
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/calibration_specs.png')

# 2. Create Clean Data
# CSV 1
pd.DataFrame({
    'timestamp': ['2023-01-01T00:00:00', '2023-01-01T01:00:00', '2023-01-01T02:00:00'],
    'Sensor_ID': ['ENV_A100', 'ENV_A100', 'ENV_A100'],
    'value': [10.0, None, 30.0]
}).to_csv('/app/corpus/clean/clean1.csv', index=False)

# CSV 2
pd.DataFrame({
    'timestamp': ['2023-01-01T00:00:00', '2023-01-01T01:00:00', '2023-01-01T02:00:00'],
    'Sensor_ID': ['ENV_B200', 'ENV_B200', 'ENV_B200'],
    'value': [100.0, None, 200.0]
}).to_csv('/app/corpus/clean/clean2.csv', index=False)

# CSV 3
pd.DataFrame({
    'timestamp': ['2023-01-01T00:00:00', '2023-01-01T01:00:00', '2023-01-01T02:00:00'],
    'Sensor_ID': ['ENV_C300', 'ENV_C300', 'ENV_C300'],
    'value': [0.0, 10.0, 20.0]
}).to_csv('/app/corpus/clean/clean3.csv', index=False)

# JSON 1
with open('/app/corpus/clean/clean4.json', 'w') as f:
    json.dump([
        {'timestamp': '2023-01-01T00:00:00', 'Sensor_ID': 'ENV_A100', 'value': 5.0},
        {'timestamp': '2023-01-01T01:00:00', 'Sensor_ID': 'ENV_A100', 'value': None},
        {'timestamp': '2023-01-01T02:00:00', 'Sensor_ID': 'ENV_A100', 'value': 15.0}
    ], f)

# JSON 2
with open('/app/corpus/clean/clean5.json', 'w') as f:
    json.dump([
        {'timestamp': '2023-01-01T00:00:00', 'Sensor_ID': 'ENV_B200', 'value': 50.0},
        {'timestamp': '2023-01-01T01:00:00', 'Sensor_ID': 'ENV_B200', 'value': 60.0}
    ], f)

# 3. Create Evil Data
# CSV 1 - Out of bounds
pd.DataFrame({
    'timestamp': ['2023-01-01T00:00:00'],
    'Sensor_ID': ['ENV_A100'],
    'value': [9999.0]
}).to_csv('/app/corpus/evil/evil1.csv', index=False)

# CSV 2 - Invalid Sensor
pd.DataFrame({
    'timestamp': ['2023-01-01T00:00:00'],
    'Sensor_ID': ['ENV_X999'],
    'value': [10.0]
}).to_csv('/app/corpus/evil/evil2.csv', index=False)

# JSON 1 - Out of bounds
with open('/app/corpus/evil/evil3.json', 'w') as f:
    json.dump([{'timestamp': '2023-01-01T00:00:00', 'Sensor_ID': 'ENV_B200', 'value': -100.0}], f)

# JSON 2 - Invalid structure
with open('/app/corpus/evil/evil4.json', 'w') as f:
    json.dump({"data": "bad"}, f)

# JSON 3 - Invalid Sensor
with open('/app/corpus/evil/evil5.json', 'w') as f:
    json.dump([{'timestamp': '2023-01-01T00:00:00', 'Sensor_ID': 'ENV_Z000', 'value': 10.0}], f)

EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
