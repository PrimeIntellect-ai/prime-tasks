#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy scikit-learn

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)
n = 1000
A = np.random.normal(0, 1, n)
B = np.random.normal(0, 1, n)
C = B + np.random.normal(0, 0.05, n)
D = np.random.normal(0, 1, n)
target = 2.0*A + 3.0*B - 1.5*D + np.random.normal(0, 0.5, n)

df = pd.DataFrame({
    'timestamp': pd.date_range(start='2023-01-01', periods=n, freq='h'),
    'sensor_A': A,
    'sensor_B': B,
    'sensor_C': C,
    'sensor_D': D,
    'target_temp': target
})

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

python3 /tmp/generate_data.py

chmod -R 777 /home/user
