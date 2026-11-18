#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import os
import numpy as np
import pandas as pd

np.random.seed(101)

data_dir = "/home/user/raw_data"
os.makedirs(data_dir, exist_ok=True)

timestamps = pd.date_range(start="2023-01-01", periods=1000, freq="min").astype(str)

# Generate base signals
sensors = [f"S_{i}" for i in range(10)]
data = {s: np.random.normal(0, 1, 1000) for s in sensors}

# Create correlations
# S_2 and S_7 highly positively correlated
data["S_7"] = 0.9 * data["S_2"] + 0.1 * np.random.normal(0, 1, 1000)
# S_4 and S_9 highly negatively correlated
data["S_9"] = -0.85 * data["S_4"] + 0.15 * np.random.normal(0, 1, 1000)

# Melt and shuffle to simulate raw CSVs
df = pd.DataFrame(data)
df["timestamp"] = timestamps
df_melted = df.melt(id_vars=["timestamp"], var_name="sensor_id", value_name="value")

# Introduce some missing values
mask = np.random.rand(len(df_melted)) < 0.01
df_melted.loc[mask, "value"] = np.nan

# Shuffle
df_melted = df_melted.sample(frac=1, random_state=101).reset_index(drop=True)

# Split into 10 CSVs
chunk_size = len(df_melted) // 10
for i in range(10):
    chunk = df_melted.iloc[i*chunk_size : (i+1)*chunk_size]
    chunk.to_csv(f"{data_dir}/readings_{i}.csv", index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
