#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        jq \
        imagemagick \
        fonts-dejavu-core

    pip3 install --default-timeout=100 pytest pandas numpy

    mkdir -p /home/user/data
    mkdir -p /app
    mkdir -p /opt/verifier

    # Generate Image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'Scaling Factor: 1.25'" /app/metrics_chart.png

    # Generate Data and Golden Output
    python3 -c "
import os, json, hashlib
import pandas as pd
import numpy as np

data = [
    (1000, 'S1', 20.5),
    (1000, 'S1', 20.5),
    (1005, 'S2', 22.1),
    (1010, 'S1', 21.0),
    (1015, 'S3', 19.8),
    (1020, 'S2', 22.5),
    (1025, 'S1', 21.5),
    (1030, 'S1', 22.0),
    (1035, 'S2', 23.0),
    (1035, 'S2', 23.0),
]

csv_data = []
json_data = []
xml_data = []

for i, (ts, sid, temp) in enumerate(data):
    if i % 3 == 0:
        csv_data.append(f'{ts},{sid},{temp}')
    elif i % 3 == 1:
        json_data.append(json.dumps({'timestamp': ts, 'sensor': sid, 'temp': temp}))
    else:
        xml_data.append(f'<log><ts>{ts}</ts><id>{sid}</id><val>{temp}</val></log>')

with open('/home/user/data/data1.csv', 'w') as f:
    f.write('timestamp,sensor_id,temperature\n' + '\n'.join(csv_data) + '\n')

with open('/home/user/data/data2.json', 'w') as f:
    f.write('\n'.join(json_data) + '\n')

with open('/home/user/data/data3.xml', 'w') as f:
    f.write('\n'.join(xml_data) + '\n')

seen = set()
dedup_data = []
for ts, sid, temp in data:
    h = hashlib.md5(f'{ts}{sid}{temp}'.encode()).hexdigest()
    if h not in seen:
        seen.add(h)
        dedup_data.append((ts, sid, temp))

df = pd.DataFrame(dedup_data, columns=['timestamp', 'sensor_id', 'temperature'])
df = df.sort_values('timestamp')

df['scaled_rolling_avg'] = df.groupby('sensor_id')['temperature'].transform(lambda x: x.rolling(3, min_periods=1).mean()) * 1.25
df['scaled_rolling_avg'] = df['scaled_rolling_avg'].round(2)

df[['timestamp', 'sensor_id', 'scaled_rolling_avg']].to_csv('/opt/verifier/golden_output.csv', index=False)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /opt/verifier
