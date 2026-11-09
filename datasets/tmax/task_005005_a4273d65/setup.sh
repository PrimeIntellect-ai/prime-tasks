#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak golang
    pip3 install pytest pandas numpy

    mkdir -p /app

    # Generate audio file
    espeak -w /app/incident_report.wav "Investigate the storage anomaly. Extract all metrics matching the prefix disk_io_"

    # Generate telemetry and ground truth
    cat << 'EOF' > /app/generate_data.py
import json
import random
import pandas as pd

metrics = ["disk_io_read", "disk_io_write", "cpu_user", "cpu_sys"]
hosts = ["app-1", "app-2"]

random.seed(42)

data = []
with open("/app/telemetry.jsonl", "w") as f:
    for i in range(1000):
        ts = 1700000000 + (i * 30) # every 30 seconds
        for host in hosts:
            record = {
                "ts": ts,
                "host": host,
                "metrics": {m: random.uniform(10.0, 100.0) for m in metrics},
                "message": "Status OK"
            }
            data.append(record)
            line = json.dumps(record)
            if random.random() < 0.1:
                line = line.replace('"Status OK"', '"Status \\uXYZW broken"')
            f.write(line + "\n")

# Generate ground truth
records = []
for d in data:
    for m in ["disk_io_read", "disk_io_write"]:
        records.append({
            "window_end_ts": d["ts"],
            "host": d["host"],
            "metric_name": m,
            "val": d["metrics"][m]
        })

df = pd.DataFrame(records)
df = df.sort_values(['host', 'metric_name', 'window_end_ts'])
df['rolling_avg'] = df.groupby(['host', 'metric_name'])['val'].transform(lambda x: x.rolling(10, min_periods=1).mean())

df = df[['window_end_ts', 'host', 'metric_name', 'rolling_avg']]
df = df.sort_values(['window_end_ts', 'host', 'metric_name'])
df.to_csv("/app/ground_truth.csv", index=False)
EOF

    python3 /app/generate_data.py

    # Create verify script
    cat << 'EOF' > /app/verify.py
import pandas as pd
import numpy as np
import sys

try:
    user_df = pd.read_csv('/home/user/aggregated_metrics.csv')
    truth_df = pd.read_csv('/app/ground_truth.csv')

    # Merge on keys
    merged = pd.merge(user_df, truth_df, on=['window_end_ts', 'host', 'metric_name'], suffixes=('_user', '_truth'))

    if len(merged) < len(truth_df) * 0.9:
        print("metric: 999.0")
        sys.exit(1)

    mse = np.mean((merged['rolling_avg_user'] - merged['rolling_avg_truth']) ** 2)
    print(f"metric: {mse}")

    if mse <= 0.01:
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    print("metric: 999.0")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
