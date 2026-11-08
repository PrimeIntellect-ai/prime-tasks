#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

# Create deterministic dataset
records = []
metrics = ['cpu', 'mem', 'disk']
servers = ['S1', 'S2', 'S3', 'S4']

# Base profiles
profiles = {
    'S1': {'cpu': 10.0, 'mem': 20.0, 'disk': 30.0},
    'S2': {'cpu': 12.0, 'mem': 22.0, 'disk': 32.0},
    'S3': {'cpu': 10.5, 'mem': 25.0, 'disk': 30.5},
    'S4': {'cpu': 80.0, 'mem': 80.0, 'disk': 80.0}
}

for ts in range(1, 11):
    for s in servers:
        for m in metrics:
            val = profiles[s][m] + (ts * 0.1) # slight trend
            records.append({'ts': ts, 'server': s, 'metric': m, 'value': val})

df = pd.DataFrame(records)

# Introduce missing values (to test interpolation/ffill/bfill)
# Remove S1 cpu at ts=3,4,5
df = df[~((df['server'] == 'S1') & (df['metric'] == 'cpu') & (df['ts'].isin([3, 4, 5])))]
# Remove S2 mem at ts=1 (tests bfill)
df = df[~((df['server'] == 'S2') & (df['metric'] == 'mem') & (df['ts'] == 1))]

# Introduce duplicates (simulate retry bug)
# Add outdated duplicate for S3 disk at ts=6
dup = pd.DataFrame([{'ts': 6, 'server': 'S3', 'metric': 'disk', 'value': 999.9}])
df = pd.concat([df, dup]) # earlier duplicate
# The correct one
correct = pd.DataFrame([{'ts': 6, 'server': 'S3', 'metric': 'disk', 'value': profiles['S3']['disk'] + 0.6}])
df = pd.concat([df, correct]) # last duplicate

df.to_csv('/home/user/raw_metrics.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
