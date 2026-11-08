#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import os
import pandas as pd
import json
import pyarrow as pa
import pyarrow.parquet as pq

os.makedirs('/home/user/raw_data', exist_ok=True)
os.makedirs('/home/user/processed', exist_ok=True)

# Data for CSV (Device A)
csv_data = pd.DataFrame({
    'date_time': ['2023-10-01 10:00:00', '2023-10-01 10:05:00', '2023-10-01 10:10:00'],
    'patient_id': ['patient_1', 'patient_1', 'patient_2'],
    'hr': [75.0, 110.0, 38.0]
})
csv_data.to_csv('/home/user/raw_data/device_a.csv', index=False)

# Data for JSON (Device B)
json_data = [
    {"ts": "2023-10-01T10:02:00Z", "uid": "patient_2", "heart_rate": 80.0},
    {"ts": "2023-10-01T10:15:00Z", "uid": "patient_1", "heart_rate": 160.0},
    {"ts": "2023-10-01T10:20:00Z", "uid": "patient_3", "heart_rate": 90.0}
]
with open('/home/user/raw_data/device_b.json', 'w') as f:
    json.dump(json_data, f)

# Data for Parquet (Device C)
pq_data = pd.DataFrame({
    'timestamp': ['2023-10-01 10:04:00', '2023-10-01 10:25:00'],
    'user': ['patient_3', 'patient_3'],
    'bpm': [65.0, 60.0]
})
pq_table = pa.Table.from_pandas(pq_data)
pq.write_table(pq_table, '/home/user/raw_data/device_c.parquet')
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
