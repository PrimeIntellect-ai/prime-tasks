#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pytesseract Pillow pandas numpy

    mkdir -p /app
    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np
from PIL import Image, ImageDraw

# 1. Generate image
img = Image.new('RGB', (400, 200), color=(73, 109, 137))
d = ImageDraw.Draw(img)
text = "SYSTEM HEALTH SUMMARY\nCPU: OK\nBASELINE_LATENCY: 45.2\nMEMORY: WARNING"
d.text((10,10), text, fill=(255,255,0))
img.save('/app/legacy_dashboard.png')

# 2. Generate data
np.random.seed(42)
periods = 10000
start_time = pd.Timestamp('2023-10-01 00:00:00', tz='UTC')
time_index = pd.date_range(start_time, periods=periods, freq='1min')

cpu_true = np.sin(np.linspace(0, 50, periods)) * 20 + 50
mem_true = np.cos(np.linspace(0, 50, periods)) * 20 + 50
latency_true = np.sin(np.linspace(0, 100, periods)) * 10 + 45.2 + np.random.normal(0, 0.5, periods)

df_true = pd.DataFrame({
    'timestamp': time_index,
    'cpu_usage': cpu_true,
    'memory_usage': mem_true,
    'latency': latency_true
})

# Create hidden truth
df_hidden = pd.DataFrame({
    'timestamp': df_true['timestamp'].dt.strftime('%Y-%m-%dT%H:%M:%SZ'),
    'normalized_latency': df_true['latency'] - 45.2
})
df_hidden.to_csv('/app/hidden_truth.csv', index=False)

# Create raw metrics
df_raw = df_true.sample(frac=0.9).sort_index()

# Introduce corrupt values
corrupt_idx = np.random.choice(df_raw.index, size=int(len(df_raw)*0.05), replace=False)
df_raw.loc[corrupt_idx, 'cpu_usage'] = -10.0

# Mix timestamp formats
timestamps = df_raw['timestamp'].copy()
unix_mask = np.random.rand(len(timestamps)) > 0.5
timestamps_iso = timestamps.dt.strftime('%Y-%m-%dT%H:%M:%SZ')
timestamps_unix = timestamps.astype('int64') // 10**9
df_raw['timestamp'] = np.where(unix_mask, timestamps_unix, timestamps_iso)

df_raw.to_csv('/home/user/raw_metrics.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
