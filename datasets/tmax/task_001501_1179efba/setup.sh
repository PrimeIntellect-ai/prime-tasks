#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Install additional system packages
apt-get install -y --no-install-recommends tesseract-ocr imagemagick fonts-dejavu-core

# Install additional Python packages
pip3 install pytesseract pandas pillow numpy

# Setup task directories
mkdir -p /app/data

# Create the calibration image
convert -size 600x100 xc:white -font DejaVu-Sans -pointsize 18 -fill black -draw "text 20,50 'SENSOR CALIBRATION: Apply linear transformation y = 3.5 * x + -1.2 to all raw readings.'" /app/calibration_specs.png

# Create the raw jsonl file with some broken unicode escapes
cat << 'EOF' > /app/create_jsonl.py
import json
import random
from datetime import datetime, timedelta

start_time = datetime(2023, 10, 1, 10, 0, 0)
bad_unicode = ["\\u00", "\\u0", "\\u20G", "\\u"]

with open("/app/data/raw_sensors.jsonl", "w") as f:
    for i in range(5000):
        t = start_time + timedelta(seconds=random.randint(0, 3600))
        # Valid data
        data = {
            "timestamp": t.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "s1": round(random.uniform(10, 50), 2),
            "s2": round(random.uniform(10, 50), 2),
            "s3": round(random.uniform(10, 50), 2)
        }
        json_str = json.dumps(data)

        # Inject broken unicode into some lines (in a dummy key so cleaning doesn't break data)
        if random.random() < 0.2:
            broken = random.choice(bad_unicode)
            json_str = json_str[:-1] + f', "notes": "broken{broken}data"' + "}"

        f.write(json_str + "\n")
EOF
python3 /app/create_jsonl.py

# Create the evaluator script (used by the verifier)
cat << 'EOF' > /app/evaluate.py
import pandas as pd
import json
import re
from datetime import datetime
import numpy as np

# Re-build ground truth
data = []
with open("/app/data/raw_sensors.jsonl", "r") as f:
    for line in f:
        # Regex clean just like agent should
        clean_line = re.sub(r'\\u[0-9a-fA-F]{0,3}[^0-9a-fA-F"]?', '', line)
        try:
            row = json.loads(clean_line)
            data.append(row)
        except:
            pass

df = pd.DataFrame(data)
df['timestamp'] = pd.to_datetime(df['timestamp'])
df['minute_timestamp'] = df['timestamp'].dt.floor('min')

long_df = df.melt(id_vars=['minute_timestamp', 'timestamp'], value_vars=['s1', 's2', 's3'], var_name='sensor_id', value_name='raw_value')
long_df = long_df.dropna(subset=['raw_value'])
long_df['calibrated_mean'] = 3.5 * pd.to_numeric(long_df['raw_value']) - 1.2

gt_agg = long_df.groupby(['minute_timestamp', 'sensor_id'])['calibrated_mean'].mean().reset_index()
gt_agg['minute_timestamp'] = gt_agg['minute_timestamp'].dt.strftime("%Y-%m-%dT%H:%M:%SZ")
gt_agg['calibrated_mean'] = gt_agg['calibrated_mean'].round(3)

try:
    agent_df = pd.read_csv("/app/processed_data.csv")
    merged = pd.merge(gt_agg, agent_df, on=['minute_timestamp', 'sensor_id'], suffixes=('_gt', '_agent'))
    mse = np.mean((merged['calibrated_mean_gt'] - merged['calibrated_mean_agent'])**2)
    print(mse)
except Exception as e:
    print(9999.0)
EOF

chmod -R 777 /app

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
