#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user', exist_ok=True)

np.random.seed(123)
n_rows = 300
n_cols = 10

# Create correlated data
base = np.random.randn(n_rows, 1)
data = base * np.random.randn(1, n_cols) + np.random.randn(n_rows, n_cols) * 0.5

df = pd.DataFrame(data, columns=[f"s{i}" for i in range(1, 11)])

# Inject schema violations
df.loc[12, 's3'] = "ERROR"
df.loc[45, 's7'] = "NaN"
df.loc[199, 's1'] = "missing"
df.loc[250, 's9'] = None

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
