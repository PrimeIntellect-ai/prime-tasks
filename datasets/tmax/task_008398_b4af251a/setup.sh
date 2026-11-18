#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest pandas

    mkdir -p /home/user/data
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/data/generate_data.py
import random
import pandas as pd

random.seed(12345)
timestamps = []
values = []

ts = 1700000000
for _ in range(20000):
    ts += random.randint(0, 4)
    val = random.uniform(10.0, 100.0)
    timestamps.append(ts)
    values.append(val)

    # Simulate ETL retries (duplicates)
    if random.random() < 0.3:
        timestamps.append(ts)
        values.append(val + random.uniform(-1.0, 1.0)) # value might differ, must take first

df = pd.DataFrame({'timestamp': timestamps, 'value': values})
df.to_csv('/home/user/data/metrics.csv', index=False)

# Generate Ground Truth
df_dedup = df.drop_duplicates(subset=['timestamp'], keep='first').copy()
df_dedup['bucket_ts'] = (df_dedup['timestamp'] // 10) * 10
bucket_stats = df_dedup.groupby('bucket_ts')['value'].mean().reset_index()
bucket_stats.rename(columns={'value': 'bucket_avg'}, inplace=True)
bucket_stats['moving_avg'] = bucket_stats['bucket_avg'].rolling(window=3, min_periods=1).mean()

with open('/home/user/data/expected_output.csv', 'w') as f:
    f.write("bucket_ts,bucket_avg,moving_avg\n")
    for _, row in bucket_stats.iterrows():
        f.write(f"{int(row['bucket_ts'])},{row['bucket_avg']:.4f},{row['moving_avg']:.4f}\n")
EOF

    python3 /home/user/data/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
