#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user/data
    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/data/generate_data.py
import pandas as pd
import numpy as np
np.random.seed(42)

df = pd.DataFrame({
    'id': range(1, 301),
    'sensor_A': np.random.randn(300).cumsum(),
    'sensor_B': np.random.randn(300).cumsum() + 0.5 * np.random.randn(300),
    'sensor_C': np.random.randn(300).cumsum() - 0.5 * np.random.randn(300)
})

# Inject anomalies (negative covariance)
df.loc[100:150, 'sensor_B'] = -df.loc[100:150, 'sensor_A']

# Shuffle to simulate out-of-order logs
df = df.sample(frac=1, random_state=42).reset_index(drop=True)

df.iloc[:100].to_csv('/home/user/data/data_1.csv', index=False)
df.iloc[100:200].to_csv('/home/user/data/data_2.csv', index=False)
df.iloc[200:].to_csv('/home/user/data/data_3.csv', index=False)
EOF

    python3 /home/user/data/generate_data.py
    rm /home/user/data/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
