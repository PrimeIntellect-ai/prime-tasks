#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
start_time = pd.Timestamp('2024-01-01T00:00:00Z')

# Generate an irregular time series
timestamps = []
levels = []
responses = []

# Bin 1: 00:00 - 00:05 (High traffic, no errors - expected winner Group B)
for _ in range(50):
    timestamps.append(start_time + pd.Timedelta(seconds=np.random.randint(0, 300)))
    levels.append('INFO')
    responses.append(np.random.normal(100, 20))

# Bin 2: 00:05 - 00:10 (Some errors - expected winner Group A)
for _ in range(30):
    timestamps.append(start_time + pd.Timedelta(seconds=300 + np.random.randint(0, 300)))
    levels.append(np.random.choice(['INFO', 'ERROR'], p=[0.7, 0.3]))
    responses.append(np.random.normal(150, 50))

# Bin 3: 00:10 - 00:15 (Empty gap)

# Bin 4: 00:15 - 00:20 (Medium traffic, no errors)
for _ in range(25):
    timestamps.append(start_time + pd.Timedelta(seconds=900 + np.random.randint(0, 300)))
    levels.append('INFO')
    responses.append(np.random.normal(110, 10))

# Bin 5: 00:20 - 00:25 (High errors - expected winner Group A)
for _ in range(40):
    timestamps.append(start_time + pd.Timedelta(seconds=1200 + np.random.randint(0, 300)))
    levels.append(np.random.choice(['INFO', 'ERROR'], p=[0.5, 0.5]))
    responses.append(np.random.normal(200, 80))

# Bin 6: 00:25 - 00:30 (Empty gap)
# Bin 7: 00:30 - 00:35 (Empty gap)

# Bin 8: 00:35 - 00:40 (Very high traffic, no errors - expected winner Group B)
for _ in range(60):
    timestamps.append(start_time + pd.Timedelta(seconds=2100 + np.random.randint(0, 300)))
    levels.append('INFO')
    responses.append(np.random.normal(95, 15))

# Bin 9: 00:40 - 00:45 (Extreme errors - expected winner Group A)
for _ in range(20):
    timestamps.append(start_time + pd.Timedelta(seconds=2400 + np.random.randint(0, 300)))
    levels.append('ERROR')
    responses.append(np.random.normal(300, 100))

# Bin 10: 00:45 - 00:50 (High traffic, no errors - expected winner Group B)
for _ in range(45):
    timestamps.append(start_time + pd.Timedelta(seconds=2700 + np.random.randint(0, 300)))
    levels.append('INFO')
    responses.append(np.random.normal(105, 25))

df = pd.DataFrame({
    'timestamp': timestamps,
    'level': levels,
    'response_ms': responses
})
df = df.sort_values('timestamp').reset_index(drop=True)
df.to_csv('/home/user/data/raw_logs.csv', index=False)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
