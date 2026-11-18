#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
pip3 install pytest pandas numpy pillow flask requests fastapi uvicorn pytesseract

mkdir -p /app/data

# Generate the configuration image
convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
    -draw "text 10,50 'PIPELINE_ID: alpha-77X'" \
    -draw "text 10,100 'INTERVAL: 30min'" \
    /app/pipeline_config.png

# Generate the CSV data
python3 -c "
import os
import pandas as pd
import numpy as np

os.makedirs('/app/data', exist_ok=True)

np.random.seed(42)
dates = pd.date_range('2023-10-01 00:00:00', '2023-10-01 03:00:00', freq='5min')
data = []
for srv in ['srv-A', 'srv-B']:
    for dt in dates:
        cpu = np.random.uniform(10, 90)
        mem = np.random.uniform(20, 80)
        data.append({'timestamp': dt, 'server_id': srv, 'cpu': cpu, 'mem': mem})

df = pd.DataFrame(data)

missing_indices = np.random.choice(df.index, size=int(len(df)*0.2), replace=False)
df.loc[missing_indices, 'cpu'] = np.nan
missing_indices_mem = np.random.choice(df.index, size=int(len(df)*0.2), replace=False)
df.loc[missing_indices_mem, 'mem'] = np.nan

df = df.sample(frac=1).reset_index(drop=True)
df.iloc[:len(df)//2].to_csv('/app/data/logs_part1.csv', index=False)
df.iloc[len(df)//2:].to_csv('/app/data/logs_part2.csv', index=False)
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
